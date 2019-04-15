//
//  deferred.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-09.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics

#if !compiler(>=5.0)
import Outcome
#endif

/// The possible states of a `Deferred`.
///
/// Must be a top-level type because Deferred is generic.

public enum DeferredState
{
  case waiting, executing, succeeded, errored
  /// Whether this `DeferredState` is determined.
  /// returns: `true` iff this `DeferredState` represents one of the states where it is determined
  public var isDetermined: Bool { return self == .succeeded || self == .errored }
}

private extension Int
{
  static let waiting =     0x0
  static let executing =   0x1
  static let determining = 0x3
  static let determined =  0x7

  var isDetermined: Bool { return self == .determined }
  var state: Int { return self & .determining }
  var waiters: UnsafeMutableRawPointer? { return UnsafeMutableRawPointer(bitPattern: self & ~0x3) }
}

/// An asynchronous computation.
///
/// A `Deferred` starts out undetermined, in the `.waiting` state.
/// It may then enter the `.executing` state, and may eventually become determined,
/// either having `.succeeded` or `.errored`.
///
/// A `Deferred` that becomes determined, will henceforth always be determined: it can no longer mutate.
///
/// The `get()` function will return the value of the computation's `Outcome` (or throw an `Error`),
/// blocking until it becomes available. If the outcome of the computation is known when `get()` is called,
/// it will return immediately.
/// The properties `value` and `error` are convenient non-throwing (but blocking) wrappers  for the `get()` method.
///
/// Closures supplied to the `enqueue` function will be called after the `Deferred` has become determined.
/// The functions `map`, `flatMap`, `notify` and others are wrappers that add functionality to the `enqueue` function.

open class Deferred<Value>
{
  let queue: DispatchQueue
  private var source: AnyObject?

  private var determined: Outcome<Value>?
  private var deferredState: AtomicInt

  deinit
  {
    let s = deferredState.load(.acquire)
    if !s.isDetermined, let w = s.waiters
    {
      deallocateWaiters(w.assumingMemoryBound(to: Waiter<Value>.self))
    }
  }

  // MARK: designated initializers

  fileprivate init<Other>(queue: DispatchQueue?, source: Deferred<Other>, beginExecution: Bool = false)
  {
    self.queue = queue ?? source.queue
    self.source = source
    determined = nil
    deferredState = AtomicInt(beginExecution ? (source.deferredState.load(.relaxed) & .executing) : 0)
  }

  fileprivate init(queue: DispatchQueue)
  {
    self.queue = queue
    source = nil
    determined = nil
    deferredState = AtomicInt(.waiting)
  }

  /// Initialize with a pre-determined `Outcome`
  ///
  /// - parameter queue: the dispatch queue upon which to execute future notifications for this `Deferred`
  /// - parameter outcome: the `Outcome` of this `Deferred`

  public init(queue: DispatchQueue, outcome: Outcome<Value>)
  {
    self.queue = queue
    source = nil
    determined = outcome
    deferredState = AtomicInt(.determined)
  }

  @available(*, deprecated, renamed: "init(queue:outcome:)")
  public convenience init(queue: DispatchQueue, result: Outcome<Value>)
  {
    self.init(queue: queue, outcome: result)
  }

  /// Initialize with a computation task to be performed on the specified queue
  ///
  /// - parameter queue: the `DispatchQueue` on which the computation (and notifications) will be executed
  /// - parameter task:  the computation to be performed

  public init(queue: DispatchQueue, task: @escaping () throws -> Value)
  {
    self.queue = queue
    source = nil
    determined = nil
    deferredState = AtomicInt(.executing)

    queue.async {
      do {
        let value = try task()
        self.determine(value: value)
      }
      catch {
        self.determine(error: error)
      }
    }
  }

  // MARK: convenience initializers

  /// Initialize with a computation task to be performed in the background
  ///
  /// - parameter qos:  the QoS at which the computation (and notifications) should be performed; defaults to the current QoS class.
  /// - parameter task: the computation to be performed

  public convenience init(qos: DispatchQoS = .current, task: @escaping () throws -> Value)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, task: task)
  }

  /// Initialize to an already determined state
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.
  /// - parameter value: the value of this `Deferred`

  public convenience init(qos: DispatchQoS = .current, value: Value)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, value: value)
  }

  /// Initialize to an already determined state
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed
  /// - parameter value: the value of this `Deferred`

  public convenience init(queue: DispatchQueue, value: Value)
  {
    self.init(queue: queue, outcome: Outcome(value: value))
  }

  /// Initialize with an Error
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.
  /// - parameter error: the error state of this `Deferred`

  public convenience init(qos: DispatchQoS = .current, error: Error)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, error: error)
  }

  /// Initialize with an Error
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed
  /// - parameter error: the error state of this `Deferred`

  public convenience init(queue: DispatchQueue, error: Error)
  {
    self.init(queue: queue, outcome: Outcome(error: error))
  }

  // MARK: state changes / determine

  /// Change the state of this `Deferred` from `.waiting` to `.executing`

  func beginExecution()
  {
    var current = deferredState.load(.relaxed)
    repeat {
      if current & .executing != 0
      { // execution state has already been marked as begun
        return
      }
    } while !deferredState.loadCAS(&current, current | .executing, .weak, .acqrel, .acquire)
  }

  /// Set the `Outcome` of this `Deferred` and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter outcome: the intended `Outcome` to determine this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  fileprivate func determine(_ outcome: Outcome<Value>) -> Bool
  {
    let originalState = deferredState.load(.relaxed).state
    guard originalState != .determining else { return false }

    let updatedState = deferredState.fetch_or(.determining, .acqrel).state
    guard updatedState != .determining else { return false }
    // this thread has exclusive access

    determined = outcome
    source = nil

    // This atomic swap operation uses memory order .acqrel.
    // "release" ordering ensures visibility of changes to `determined` above to another thread.
    // "acquire" ordering ensures visibility of changes to `waitQueue` from another thread.
    // Any atomic load of `waiters` that precedes a possible use of `determined`
    // *must* use memory order .acquire.
    let state = deferredState.swap(.determined, .acqrel)
    // precondition(state.isDetermined == false)
    let waitQueue = state.waiters?.assumingMemoryBound(to: Waiter<Value>.self)
    notifyWaiters(queue, waitQueue, outcome)

    // precondition(waiters.load() == .determined, "waiters.pointer has incorrect value \(String(describing: waiters.load()))")

    // The outcome has been determined
    return true
  }

  /// Set the value of this `Deferred` and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  fileprivate func determine(value: Value) -> Bool
  {
    return determine(Outcome(value: value))
  }

  /// Set this `Deferred` to an error and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter error: the intended error for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  fileprivate func determine(error: Error) -> Bool
  {
    return determine(Outcome(error: error))
  }

  // MARK: public interface

  /// Enqueue a closure to be performed asynchronously after this `Deferred` becomes determined.
  ///
  /// This operation is lock-free and thread-safe.
  /// Multiple threads can call this method at once; they will succeed in turn.
  ///
  /// Before `determine()` has been called, the effect of `enqueue()` is to add the closure
  /// to a list of closures to be called once this `Deferred` has a determined outcome.
  ///
  /// After `determine()` has been called, the effect of `enqueue()` is to immediately
  /// enqueue the closure for execution.
  ///
  /// Note that the enqueued closure will does not modify `task`, and will not extend the lifetime of `self`.
  /// If you need to extend the lifetime of `self` until `task` executes, use `notify()`.
  ///
  /// - parameter queue: the `DispatchQueue` on which to dispatch this notification when ready; defaults to `self`'s queue.
  /// - parameter boostQoS: whether `enqueue` should attempt to boost the QoS if `queue.qos` is higher than `self.qos`; defaults to `true`
  /// - parameter task: a closure to be executed after `self` becomes determined.
  /// - parameter outcome: the determined `Outcome` of `self`

  open func enqueue(queue: DispatchQueue? = nil, boostQoS: Bool = true, task: @escaping (_ outcome: Outcome<Value>) -> Void)
  {
    var state = deferredState.load(.acquire)
    if !state.isDetermined
    {
      let waiter = UnsafeMutablePointer<Waiter<Value>>.allocate(capacity: 1)
      waiter.initialize(to: Waiter(queue, task))

      if boostQoS, let qos = queue?.qos, qos > self.queue.qos
      { // try to raise `self.queue`'s QoS if the notification needs to execute at a higher QoS
        self.queue.async(qos: qos, flags: [.enforceQoS, .barrier], execute: {})
      }

      repeat {
        waiter.pointee.next = state.waiters?.assumingMemoryBound(to: Waiter<Value>.self)
        let newState = Int(bitPattern: waiter) | (state & .determining)
        if deferredState.loadCAS(&state, newState, .weak, .release, .relaxed)
        { // waiter is now enqueued; it will be deallocated at a later time by notifyWaiters()
          return
        }
      } while !state.isDetermined

      // this Deferred has become determined; clean up
      waiter.deinitialize(count: 1)
      waiter.deallocate()
      _ = deferredState.load(.acquire)
    }

    // this Deferred is determined
    let q = queue ?? self.queue
    q.async(execute: { [outcome = determined!] in task(outcome) })
  }

  /// Enqueue a notification to be performed asynchronously after this `Deferred` becomes determined.
  ///
  /// The enqueued closure will extend the lifetime of `self` until `task` completes.
  ///
  /// - parameter queue: the `DispatchQueue` on which to dispatch this notification when ready; defaults to `self`'s queue.
  /// - parameter task: a closure to be executed as a notification
  /// - parameter outcome: the determined `Outcome` of `self`

  public func notify(queue: DispatchQueue? = nil, task: @escaping (_ outcome: Outcome<Value>) -> Void)
  {
    enqueue(queue: queue, task: { outcome in withExtendedLifetime(self) { task(outcome) } })
  }

  /// Query the current state of this `Deferred`
  /// - returns: a `DeferredState` that describes this `Deferred`

  public var state: DeferredState {
    let state = deferredState.load(.acquire)
    return state.isDetermined ?
      (determined!.isValue ? .succeeded : .errored) :
      (state.state == .waiting ? .waiting : .executing )
  }

  /// Query whether this `Deferred` has become determined.
  /// - returns: `true` iff this `Deferred` has become determined.

  public var isDetermined: Bool {
    return deferredState.load(.relaxed).isDetermined
  }

  /// Attempt to cancel the current operation, and report on whether cancellation happened successfully.
  ///
  /// A successful cancellation will result in a `Deferred` equivalent to as if it had been initialized as follows:
  /// ```
  /// Deferred<Value>(error: DeferredError.canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation. Defaults to an empty `String`.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  open func cancel(_ reason: String = "") -> Bool
  {
    return cancel(.canceled(reason))
  }

  /// Attempt to cancel the current operation, and report on whether cancellation happened successfully.
  ///
  /// - parameter error: a `DeferredError` detailing the reason for the attempted cancellation.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  open func cancel(_ error: DeferredError) -> Bool
  {
    return determine(error: error)
  }

  /// Get this `Deferred`'s determined `Outcome`, blocking if necessary until it exists.
  ///
  /// When called on a `Deferred` that is already determined, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not determined, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s determined `Outcome`

  public var outcome: Outcome<Value> {
    if deferredState.load(.acquire).isDetermined == false
    {
      if let current = DispatchQoS.QoSClass.current, current > queue.qos.qosClass
      { // try to boost the QoS class of the running task if it is lower than the current thread's QoS
        queue.async(qos: DispatchQoS(qosClass: current, relativePriority: 0),
                    flags: [.enforceQoS, .barrier], execute: {})
      }
      let s = DispatchSemaphore(value: 0)
      self.enqueue(boostQoS: false, task: { _ in s.signal() })
      s.wait()
      _ = deferredState.load(.acquire)
    }

    // this Deferred is determined
    return determined!
  }

  @available(*, deprecated, renamed: "outcome")
  public var result: Outcome<Value> { return self.outcome }

  /// Get this `Deferred`'s value, blocking if necessary until it becomes determined.
  ///
  /// If the `Deferred` is determined with an `Error`, that `Error` is thrown.
  ///
  /// When called on a `Deferred` that is already determined, this call is non-blocking.
  /// When called on a `Deferred` that is not determined, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s determined value, or a thrown `Error`

  public func get() throws -> Value
  {
    return try outcome.get()
  }

  /// Get this `Deferred`'s `Outcome` if has been determined, `nil` otherwise.
  ///
  /// This call is non-blocking and wait-free.
  ///
  /// - returns: this `Deferred`'s determined `Outcome`, or `nil`

  public func peek() -> Outcome<Value>?
  {
    if deferredState.load(.acquire).isDetermined
    {
      return determined
    }
    return nil
  }

  /// Get this `Deferred`'s value, blocking if necessary until it becomes determined.
  ///
  /// If the `Deferred` is determined with an `Error`, return nil.
  ///
  /// When called on a `Deferred` that is already determined, this call is non-blocking.
  /// When called on a `Deferred` that is not determined, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s determined value, or `nil`

  public var value: Value? {
    return outcome.value
  }

  /// Get this `Deferred`'s error state, blocking if necessary until it becomes determined.
  ///
  /// If the `Deferred` is determined with a `Value`, return nil.
  ///
  /// When called on a `Deferred` that is already determined, this call is non-blocking.
  /// When called on a `Deferred` that is not determined, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s determined error state, or `nil`

  public var error: Error? {
    return outcome.error
  }

  /// Get the QoS of this `Deferred`'s queue
  /// - returns: the QoS of this `Deferred`'s queue

  public var qos: DispatchQoS { return self.queue.qos }
}


/// A mapped `Deferred`

class Map<Value>: Deferred<Value>
{
  /// Initialize with a `Deferred` source and a transform to be computed in the background
  ///
  /// This constructor is used by `map`
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued; use `source.queue` if `nil`
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose outcome is represented by this `Deferred`
  /// - parameter value:     the value to be transformed for a new `Deferred`

  init<U>(queue: DispatchQueue?, source: Deferred<U>, transform: @escaping (_ value: U) throws -> Value)
  {
    super.init(queue: queue, source: source)

    source.enqueue(queue: queue) {
      [weak self] outcome in
      guard let this = self else { return }
      if this.isDetermined { return }
      this.beginExecution()
      do {
        let value = try outcome.get()
        let transformed = try transform(value)
        this.determine(value: transformed)
      }
      catch {
        this.determine(error: error)
      }
    }
  }
}

open class Transferred<Value>: Deferred<Value>
{
  /// Transfer a `Deferred` `Outcome` to a new `Deferred` that notifies on a new queue.
  ///
  /// Acts like a fast path for a Map with no transform.
  ///
  /// This constructor is used by `enqueuing(on:)`
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the new `Deferred` should dispatch notifications; use `source.queue` if `nil`
  /// - parameter source:    the `Deferred` whose value will be transferred into a new instance.

  public init(queue: DispatchQueue? = nil, source: Deferred<Value>)
  {
    if let outcome = source.peek()
    {
      super.init(queue: queue ?? source.queue, outcome: outcome)
    }
    else
    {
      super.init(queue: queue ?? source.queue, source: source, beginExecution: true)
      source.enqueue(queue: queue, boostQoS: false,
                     task: { [weak self] outcome in self?.determine(outcome) })
    }
  }
}

class Flatten<Value>: Deferred<Value>
{
  /// Flatten a Deferred<Deferred<Value>> to a Deferred<Value>.
  ///
  /// In the right conditions, acts like a fast path for a flatMap with no transform.
  ///
  /// This constructor is used by `flatten()`
  ///
  /// - parameter queue: the `DispatchQueue` onto which the new `Deferred` should dispatch notifications; use `source.queue` if `nil`
  /// - parameter source: the `Deferred` whose value will be transferred into a new instance.

  init(queue: DispatchQueue? = nil, source: Deferred<Deferred<Value>>)
  {
    if let outcome = source.peek()
    {
      let mine = queue ?? source.queue
      do {
        let deferred = try outcome.get()
        if let outcome = deferred.peek()
        {
          super.init(queue: mine, outcome: outcome)
        }
        else
        {
          super.init(queue: mine, source: deferred, beginExecution: true)
          deferred.enqueue(queue: mine, boostQoS: false, task: { [weak self] in self?.determine($0) })
        }
      }
      catch {
        super.init(queue: mine, outcome: Outcome(error: error))
      }
      return
    }

    super.init(queue: queue, source: source)
    source.enqueue(queue: queue) {
      [weak self] outcome in
      do {
        let deferred = try outcome.get()
        if let outcome = deferred.peek()
        {
          self?.determine(outcome)
        }
        else
        {
          deferred.notify(queue: queue, task: { [weak self] in self?.determine($0) })
        }
      }
      catch {
        self?.determine(error: error)
      }
    }
  }

  /// Flatten a Deferred<Deferred<Value>> to a Deferred<Value>.
  ///
  /// In the right conditions, acts like a fast path for a flatMap with no transform.
  ///
  /// - parameter source: the `Deferred` whose value will be transferred into a new instance.

  convenience init(_ source: Deferred<Deferred<Value>>)
  {
    self.init(queue: nil, source: source)
  }
}

class Bind<Value>: Deferred<Value>
{
  /// Initialize with a `Deferred` source and a transform to be computed in the background
  ///
  /// This constructor is used by `flatMap`
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued; use `source.queue` if `nil`
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose outcome is represented by this `Deferred`
  /// - parameter value:     the value to be transformed for a new `Deferred`

  init<U>(queue: DispatchQueue?, source: Deferred<U>, transform: @escaping (_ value: U) throws -> Deferred<Value>)
  {
    super.init(queue: queue, source: source)

    source.enqueue(queue: queue) {
      [weak self] outcome in
      guard let this = self else { return }
      if this.isDetermined { return }
      this.beginExecution()
      do {
        let value = try outcome.get()
        let transformed = try transform(value)
        transformed.notify(queue: queue) {
          [weak this] transformed in
          this?.determine(transformed)
        }
      }
      catch {
        this.determine(error: error)
      }
    }
  }
}

class Recover<Value>: Deferred<Value>
{
  /// Initialize with a `Deferred` source and a transform to be computed in the background
  ///
  /// This constructor is used by `recover` -- flatMap for the `Error` path.
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued; use `source.queue` if `nil`
  /// - parameter source:    the `Deferred` whose error should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.error` and whose outcome is represented by this `Deferred`
  /// - parameter error:     the Error to be transformed for a new `Deferred`

  init(queue: DispatchQueue?, source: Deferred<Value>, transform: @escaping (_ error: Error) throws -> Deferred<Value>)
  {
    super.init(queue: queue, source: source)

    source.enqueue(queue: queue) {
      [weak self] outcome in
      guard let this = self else { return }
      if this.isDetermined { return }
      this.beginExecution()
      if let error = outcome.error
      {
        do {
          let transformed = try transform(error)
          transformed.notify(queue: queue) {
            [weak this] transformed in
            this?.determine(transformed)
          }
        }
        catch {
          this.determine(error: error)
        }
      }
      else
      {
        this.determine(outcome)
      }
    }
  }
}

/// A `Deferred` that applies a `Deferred` transform onto its input

class Apply<Value>: Deferred<Value>
{
  /// Initialize with a `Deferred` source and a transform to be computed in the background
  ///
  /// This constructor is used by `apply`
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued; use `source.queue` if `nil`
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose outcome is represented by this `Deferred`
  /// - parameter value:     the value to be transformed for a new `Deferred`

  init<U>(queue: DispatchQueue?, source: Deferred<U>, transform: Deferred<(_ value: U) throws -> Value>)
  {
    super.init(queue: queue, source: source)

    source.enqueue(queue: queue) {
      [weak self] outcome in
      guard let this = self else { return }
      if this.isDetermined { return }
      do {
        let value = try outcome.get()
        transform.notify(queue: queue) {
          [weak this] transform in
          guard let this = this else { return }
          if this.isDetermined { return }
          this.beginExecution()
          do {
            let transform = try transform.get()
            let transformed = try transform(value)
            this.determine(value: transformed)
          }
          catch {
            this.determine(error: error)
          }
        }
      }
      catch {
        this.determine(error: error)
      }
    }
  }
}

/// A `Deferred` with a time delay

class Delay<Value>: Deferred<Value>
{
  /// Initialize with a `Deferred` source and a time after which this `Deferred` may become determined.
  ///
  /// The determination could be delayed further if `source` has not become determined yet,
  /// but it will not happen earlier than the time referred to by `until`.
  ///
  /// This constructor is used by `delay`
  ///
  /// - parameter queue:  the `DispatchQueue` onto which the computation should be enqueued; use `source.queue` if `nil`
  /// - parameter source: the `Deferred` whose value should be delayed
  /// - parameter until:  the target time until which the determination of this `Deferred` will be delayed

  init(queue: DispatchQueue?, source: Deferred<Value>, until time: DispatchTime)
  {
    super.init(queue: queue, source: source)

    source.enqueue(queue: queue, boostQoS: false) {
      [weak self] outcome in
      guard let this = self, (this.isDetermined == false) else { return }

      if outcome.isError
      {
        this.determine(outcome)
        return
      }

      this.beginExecution()
      if time == .distantFuture { return }
      // enqueue block only if can get executed
      if time > .now()
      {
        this.queue.asyncAfter(deadline: time) {
          [weak this] in
          this?.determine(outcome)
        }
      }
      else
      {
        this.determine(outcome)
      }
    }
  }
}

public struct Resolver<Value>
{
  private weak var deferred: Deferred<Value>?

  fileprivate init(_ deferred: Deferred<Value>)
  {
    self.deferred = deferred
  }

  /// Set the value of our `Deferred` and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  public func determine(_ outcome: Outcome<Value>) -> Bool
  {
    return deferred?.determine(outcome) ?? false
  }

  /// Set the value of our `Deferred` and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  public func determine(value: Value) -> Bool
  {
    return determine(Outcome(value: value))
  }

  /// Set our `Deferred` to an error and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter error: the intended error for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  public func determine(error: Error) -> Bool
  {
    return determine(Outcome(error: error))
  }

  /// Attempt to cancel the current operation, and report on whether cancellation happened successfully.
  ///
  /// A successful cancellation will result in a `Deferred` equivalent to as if it had been initialized as follows:
  /// ```
  /// Deferred<Value>(error: DeferredError.canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation. Defaults to an empty `String`.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  public func cancel(_ reason: String = "") -> Bool
  {
    return determine(Outcome(error: DeferredError.canceled(reason)))
  }

  /// Change the state of our `Deferred` from `.waiting` to `.executing`

  public func beginExecution()
  {
    deferred?.beginExecution()
  }

  /// Enqueue a notification to be performed asynchronously after our `Deferred` becomes determined.
  ///
  /// - parameter queue: the `DispatchQueue` on which to dispatch this notification when ready; defaults to `self`'s queue.
  /// - parameter task: a closure to be executed as a notification
  /// - parameter outcome: the determined `Outcome` of our `Deferred`

  public func notify(task: @escaping (_ outcome: Outcome<Value>) -> Void)
  {
    deferred?.enqueue(task: task)
  }
}

/// A `Deferred` to be determined (`TBD`) manually.

open class TBD<Value>: Deferred<Value>
{
  /// Initialize an undetermined `Deferred`, `TBD`.
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed

  public init(queue: DispatchQueue, execute: (Resolver<Value>) -> Void)
  {
    super.init(queue: queue)
    execute(Resolver(self))
  }

  /// Initialize an undetermined `Deferred`, `TBD`.
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.

  public init(qos: DispatchQoS = .current, execute: (Resolver<Value>) -> Void)
  {
    let queue = DispatchQueue(label: "tbd", qos: qos)
    super.init(queue: queue)
    execute(Resolver(self))
  }

  public static func CreatePair(queue: DispatchQueue) -> (Resolver<Value>, Deferred<Value>)
  {
    let d = Deferred<Value>(queue: queue)
    return (Resolver(d), d)
  }

  public static func CreatePair(qos: DispatchQoS = .current) -> (Resolver<Value>, Deferred<Value>)
  {
    let queue = DispatchQueue(label: "tbd", qos: qos)
    return CreatePair(queue: queue)
  }
}
