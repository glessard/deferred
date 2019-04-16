//
//  deferred.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-09.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics

/// The possible states of a `Deferred`.
///
/// Must be a top-level type because Deferred is generic.

public enum DeferredState
{
  case waiting, executing, succeeded, errored
  /// Whether this `DeferredState` is resolved.
  /// returns: `true` iff this `DeferredState` represents one of the states where it is resolved
  public var isResolved: Bool { return self == .succeeded || self == .errored }
}

private extension Int
{
  static let waiting =   0x0
  static let executing = 0x1
  static let resolving = 0x3
  static let resolved =  0x7

  var isResolved: Bool { return self == .resolved }
  var state: Int { return self & .resolving }
  var waiters: UnsafeMutableRawPointer? { return UnsafeMutableRawPointer(bitPattern: self & ~0x3) }
}

/// An asynchronous computation.
///
/// A `Deferred` starts out unresolved, in the `.waiting` state.
/// It may then enter the `.executing` state, and may eventually become resolved,
/// either having `.succeeded` or `.errored`.
///
/// A `Deferred` that becomes resolved, will henceforth always be resolved: it can no longer mutate.
///
/// The `get()` function will return the value of the computation's `Result` (or throw an `Error`),
/// blocking until it becomes available. If the result of the computation is known when `get()` is called,
/// it will return immediately.
/// The properties `value` and `error` are convenient non-throwing (but blocking) wrappers  for the `get()` method.
///
/// Closures supplied to the `enqueue` function will be called after the `Deferred` has become resolved.
/// The functions `map`, `flatMap`, `notify` and others are wrappers that add functionality to the `enqueue` function.

open class Deferred<Value>
{
  let queue: DispatchQueue
  private var source: AnyObject?

  private var resolved: Result<Value, Error>?
  private var deferredState: AtomicInt

  deinit
  {
    let s = deferredState.load(.acquire)
    if !s.isResolved, let w = s.waiters
    {
      deallocateWaiters(w.assumingMemoryBound(to: Waiter<Value>.self))
    }
  }

  // MARK: designated initializers

  fileprivate init<Other>(queue: DispatchQueue?, source: Deferred<Other>, beginExecution: Bool = false)
  {
    self.queue = queue ?? source.queue
    self.source = source
    resolved = nil
    deferredState = AtomicInt(beginExecution ? (source.deferredState.load(.relaxed) & .executing) : 0)
  }

  fileprivate init(queue: DispatchQueue, source: AnyObject? = nil)
  {
    self.queue = queue
    self.source = source
    resolved = nil
    deferredState = AtomicInt(.waiting)
  }

  /// Initialize as resolved with a `Result`
  ///
  /// - parameter queue: the dispatch queue upon which to execute future notifications for this `Deferred`
  /// - parameter result: the `Result` of this `Deferred`

  public init(queue: DispatchQueue, result: Result<Value, Error>)
  {
    self.queue = queue
    source = nil
    resolved = result
    deferredState = AtomicInt(.resolved)
  }

  /// Initialize with a task to be computed on the specified queue
  ///
  /// - parameter queue: the `DispatchQueue` on which the computation (and notifications) will be executed
  /// - parameter task:  the computation to be performed

  public init(queue: DispatchQueue, task: @escaping () throws -> Value)
  {
    self.queue = queue
    source = nil
    resolved = nil
    deferredState = AtomicInt(.executing)

    queue.async {
      do {
        let value = try task()
        self.resolve(value: value)
      }
      catch {
        self.resolve(error: error)
      }
    }
  }

  // MARK: convenience initializers

  /// Initialize with a task to be computed in the background
  ///
  /// - parameter qos:  the QoS at which the computation (and notifications) should be performed; defaults to the current QoS class.
  /// - parameter task: a computation to be performed

  public convenience init(qos: DispatchQoS = .current, task: @escaping () throws -> Value)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, task: task)
  }

  /// Initialize as resolved with a `Value`
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.
  /// - parameter value: the value of this `Deferred`

  public convenience init(qos: DispatchQoS = .current, value: Value)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, value: value)
  }

  /// Initialize as resolved with a `Value`
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed
  /// - parameter value: the value of this `Deferred`

  public convenience init(queue: DispatchQueue, value: Value)
  {
    self.init(queue: queue, result: Result<Value, Error>(value: value))
  }

  /// Initialize as resolved with an `Error`
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.
  /// - parameter error: the error state of this `Deferred`

  public convenience init(qos: DispatchQoS = .current, error: Error)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, error: error)
  }

  /// Initialize as resolved with an `Error`
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed
  /// - parameter error: the error state of this `Deferred`

  public convenience init(queue: DispatchQueue, error: Error)
  {
    self.init(queue: queue, result: Result<Value, Error>(error: error))
  }

  // MARK: state changes / resolve

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

  /// Set the `Result` of this `Deferred` and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve()` will fail and return `false`.
  ///
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter result: the intended `Result` to resolve this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  fileprivate func resolve(_ result: Result<Value, Error>) -> Bool
  {
    let originalState = deferredState.load(.relaxed).state
    guard originalState != .resolving else { return false }

    let updatedState = deferredState.fetch_or(.resolving, .acqrel).state
    guard updatedState != .resolving else { return false }
    // this thread has exclusive access

    resolved = result
    source = nil

    // This atomic swap operation uses memory order .acqrel.
    // "release" ordering ensures visibility of changes to `resolved` above to another thread.
    // "acquire" ordering ensures visibility of changes to `waitQueue` from another thread.
    // Any atomic load of `waiters` that precedes a possible use of `resolved`
    // *must* use memory order .acquire.
    let state = deferredState.swap(.resolved, .acqrel)
    // precondition(state.isResolved == false)
    let waitQueue = state.waiters?.assumingMemoryBound(to: Waiter<Value>.self)
    notifyWaiters(queue, waitQueue, result)

    // precondition(waiters.load() == .resolved, "waiters.pointer has incorrect value \(String(describing: waiters.load()))")

    // This `Deferred` has been resolved
    return true
  }

  /// Resolve this `Deferred` with a `Value` and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve()` will fail and return `false`.
  ///
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  fileprivate func resolve(value: Value) -> Bool
  {
    return resolve(Result<Value, Error>(value: value))
  }

  /// Resolve this `Deferred` with an `Error` and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve()` will fail and return `false`.
  ///
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter error: the intended error for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  fileprivate func resolve(error: Error) -> Bool
  {
    return resolve(Result<Value, Error>(error: error))
  }

  // MARK: public interface

  /// Enqueue a closure to be performed asynchronously after this `Deferred` becomes resolved.
  ///
  /// This operation is lock-free and thread-safe.
  /// Multiple threads can call this method at once; they will succeed in turn.
  ///
  /// Before `self` has been resolved, the effect of `enqueue()` is to add the closure
  /// to a list of closures to be called once this `Deferred` has been resolved.
  ///
  /// Before `self` has been resolved, the effect of `enqueue()` is to immediately
  /// enqueue the closure for execution.
  ///
  /// Note that the enqueued closure will does not modify `task`, and will not extend the lifetime of `self`.
  /// If you need to extend the lifetime of `self` until the closure executes, use `notify()`.
  ///
  /// - parameter queue: the `DispatchQueue` on which to dispatch this notification when ready; defaults to `self`'s queue.
  /// - parameter boostQoS: whether `enqueue` should attempt to boost the QoS if `queue.qos` is higher than `self.qos`; defaults to `true`
  /// - parameter task: a closure to be executed after `self` becomes resolved.
  /// - parameter result: the `Result` of `self`

  open func enqueue(queue: DispatchQueue? = nil, boostQoS: Bool = true, task: @escaping (_ result: Result<Value, Error>) -> Void)
  {
    var state = deferredState.load(.acquire)
    if !state.isResolved
    {
      let waiter = UnsafeMutablePointer<Waiter<Value>>.allocate(capacity: 1)
      waiter.initialize(to: Waiter(queue, task))

      if boostQoS, let qos = queue?.qos, qos > self.queue.qos
      { // try to raise `self.queue`'s QoS if the notification needs to execute at a higher QoS
        self.queue.async(qos: qos, flags: [.enforceQoS, .barrier], execute: {})
      }

      repeat {
        waiter.pointee.next = state.waiters?.assumingMemoryBound(to: Waiter<Value>.self)
        let newState = Int(bitPattern: waiter) | (state & .resolving)
        if deferredState.loadCAS(&state, newState, .weak, .release, .relaxed)
        { // waiter is now enqueued; it will be deallocated at a later time by notifyWaiters()
          return
        }
      } while !state.isResolved

      // this Deferred has become resolved; clean up
      waiter.deinitialize(count: 1)
      waiter.deallocate()
      _ = deferredState.load(.acquire)
    }

    // this Deferred is resolved
    let q = queue ?? self.queue
    q.async(execute: { [result = resolved!] in task(result) })
  }

  /// Enqueue a notification to be performed asynchronously after this `Deferred` becomes resolved.
  ///
  /// The enqueued closure will extend the lifetime of this `Deferred` until `task` completes.
  ///
  /// - parameter queue: the `DispatchQueue` on which to dispatch this notification when ready; defaults to `self`'s queue.
  /// - parameter task: a closure to be executed as a notification
  /// - parameter result: the `Result` of this `Deferred`

  public func notify(queue: DispatchQueue? = nil, task: @escaping (_ result: Result<Value, Error>) -> Void)
  {
    enqueue(queue: queue, task: { result in withExtendedLifetime(self) { task(result) } })
  }

  /// Query the current state of this `Deferred`
  /// - returns: a `DeferredState` that describes this `Deferred`

  public var state: DeferredState {
    let state = deferredState.load(.acquire)
    return state.isResolved ?
      (resolved!.isValue ? .succeeded : .errored) :
      (state.state == .waiting ? .waiting : .executing )
  }

  /// Query whether this `Deferred` has become resolved.
  /// - returns: `true` iff this `Deferred` has become resolved.

  public var isResolved: Bool {
    return deferredState.load(.relaxed).isResolved
  }

  /// Attempt to cancel this `Deferred`
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

  /// Attempt to cancel this `Deferred`
  ///
  /// - parameter error: a `DeferredError` detailing the reason for the attempted cancellation.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  open func cancel(_ error: DeferredError) -> Bool
  {
    return resolve(error: error)
  }

  /// Get this `Deferred`'s `Result`, blocking if necessary until it exists.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s `Result`

  public var result: Result<Value, Error> {
    if deferredState.load(.acquire).isResolved == false
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

    // this Deferred is resolved
    return resolved!
  }

  /// Get this `Deferred`'s value, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with an `Error`, that `Error` is thrown.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved `Value`, or a thrown `Error`

  public func get() throws -> Value
  {
    return try result.get()
  }

  /// Get this `Deferred`'s `Result` if has been resolved, `nil` otherwise.
  ///
  /// This call is non-blocking and wait-free.
  ///
  /// - returns: this `Deferred`'s `Result`, or `nil`

  public func peek() -> Result<Value, Error>?
  {
    if deferredState.load(.acquire).isResolved
    {
      return resolved
    }
    return nil
  }

  /// Get this `Deferred`'s value, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with an `Error`, return nil.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved value, or `nil`

  public var value: Value? {
    return result.value
  }

  /// Get this `Deferred`'s error state, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with a `Value`, return nil.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved error state, or `nil`

  public var error: Error? {
    return result.error
  }

  /// Get the QoS of this `Deferred`'s queue
  /// - returns: the QoS of this `Deferred`'s queue

  public var qos: DispatchQoS { return self.queue.qos }
}


open class Transferred<Value>: Deferred<Value>
{
  /// Transfer a `Deferred` `Result` to a new `Deferred` that notifies on a new queue.
  ///
  /// Acts like a fast path for a Map with no transform.
  ///
  /// This constructor is used by `enqueuing(on:)`
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the new `Deferred` should dispatch notifications; use `source.queue` if `nil`
  /// - parameter source:    the `Deferred` whose value will be transferred into a new instance.

  public init(queue: DispatchQueue? = nil, source: Deferred<Value>)
  {
    if let result = source.peek()
    {
      super.init(queue: queue ?? source.queue, result: result)
    }
    else
    {
      super.init(queue: queue ?? source.queue, source: source, beginExecution: true)
      source.enqueue(queue: queue, boostQoS: false,
                     task: { [weak self] result in self?.resolve(result) })
    }
  }
}

/// A `Deferred` with a time delay

class Delay<Value>: Deferred<Value>
{
  /// Initialize with a `Deferred` source and a time after which this `Deferred` may become resolved.
  ///
  /// The resolution could be delayed further if `source` has not become resolved yet,
  /// but it will not happen earlier than the time referred to by `until`.
  ///
  /// This constructor is used by `delay`
  ///
  /// - parameter queue:  the `DispatchQueue` onto which the computation should be enqueued; use `source.queue` if `nil`
  /// - parameter source: the `Deferred` whose value should be delayed
  /// - parameter until:  the target time until which the resolution of this `Deferred` will be delayed

  init(queue: DispatchQueue?, source: Deferred<Value>, until time: DispatchTime)
  {
    super.init(queue: queue, source: source)

    source.enqueue(queue: queue, boostQoS: false) {
      [weak self] result in
      guard let this = self, (this.isResolved == false) else { return }

      if result.isError
      {
        this.resolve(result)
        return
      }

      this.beginExecution()
      if time == .distantFuture { return }
      // enqueue block only if can get executed
      if time > .now()
      {
        this.queue.asyncAfter(deadline: time) {
          [weak this] in
          this?.resolve(result)
        }
      }
      else
      {
        this.resolve(result)
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
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  public func resolve(_ result: Result<Value, Error>) -> Bool
  {
    return deferred?.resolve(result) ?? false
  }

  /// Set the value of our `Deferred` and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  public func resolve(value: Value) -> Bool
  {
    return resolve(Result<Value, Error>(value: value))
  }

  /// Set our `Deferred` to an error and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter error: the intended error for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  public func resolve(error: Error) -> Bool
  {
    return resolve(Result<Value, Error>(error: error))
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
    return resolve(Result<Value, Error>(error: DeferredError.canceled(reason)))
  }

  /// Change the state of our `Deferred` from `.waiting` to `.executing`

  public func beginExecution()
  {
    deferred?.beginExecution()
  }

  /// Query whether the underlying `Deferred` still exists and is also unresolved

  public var needsResolution: Bool { return deferred?.isResolved == false }

  /// Enqueue a notification to be performed asynchronously after our `Deferred` becomes resolved.
  ///
  /// - parameter queue: the `DispatchQueue` on which to dispatch this notification when ready; defaults to `self`'s queue.
  /// - parameter task: a closure to be executed as a notification
  /// - parameter result: the `Result` to which our `Deferred` was resolved

  public func notify(task: @escaping (_ result: Result<Value, Error>) -> Void)
  {
    deferred?.enqueue(task: task)
  }
}

/// A `Deferred` to be resolved (`TBD`) manually.

open class TBD<Value>: Deferred<Value>
{
  /// Initialize an unresolved `Deferred`, `TBD`.
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed

  public init(queue: DispatchQueue, source: AnyObject? = nil, execute: (Resolver<Value>) -> Void)
  {
    super.init(queue: queue, source: source)
    execute(Resolver(self))
  }

  /// Initialize an unresolved `Deferred`, `TBD`.
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.

  public init(qos: DispatchQoS = .current, source: AnyObject? = nil, execute: (Resolver<Value>) -> Void)
  {
    let queue = DispatchQueue(label: "tbd", qos: qos)
    super.init(queue: queue, source: source)
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
