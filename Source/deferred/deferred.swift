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
  public var isDetermined: Bool { return self == .succeeded || self == .errored }
}

extension UnsafeMutableRawPointer
{
  fileprivate static let determined = UnsafeMutableRawPointer(bitPattern: 0x7)!
}

/// An asynchronous computation.
///
/// A `Deferred` starts out undetermined, in the `.waiting` state.
/// It may then enter the `.executing` state, and will eventually become `.determined`.
/// Once it is `.determined`, it is ready to supply a result.
///
/// The `get()` method and the `value` and `error` properties can be used to obtain
/// the result of a `Deferred`, blocking if necessary until a result is available.
/// If the result is ready when those are called, they return immediately.
///
/// A closure supplied to the `enqueue` method will be called after the `Deferred` has become determined.

open class Deferred<Value>
{
  fileprivate let queue: DispatchQueue
  private var source: AnyObject?

  private var determination: Determined<Value>?
  private var waiters = AtomicMutableRawPointer()
  private var stateid = AtomicInt32()

  deinit
  {
    if let w = waiters.load(.acquire), w != .determined
    {
      deallocateWaiters(w.assumingMemoryBound(to: Waiter<Value>.self))
    }
  }

  // MARK: designated initializers

  fileprivate init<Other>(queue: DispatchQueue? = nil, source: Deferred<Other>, beginExecution: Bool = false)
  {
    self.queue = queue ?? source.queue
    self.source = source
    determination = nil
    waiters.initialize(nil)
    stateid.initialize(beginExecution ? 1:0)
  }

  internal init(queue: DispatchQueue)
  {
    self.queue = queue
    source = nil
    determination = nil
    waiters.initialize(nil)
    stateid.initialize(0)
  }

  /// Initialize to an already determined state
  ///
  /// - parameter queue:  the dispatch queue upon which to execute future notifications for this `Deferred`
  /// - parameter result: the result of this `Deferred`

  public init(queue: DispatchQueue, result: Determined<Value>)
  {
    self.queue = queue
    source = nil
    determination = result
    waiters.initialize(.determined)
    stateid.initialize(2)
  }

  // MARK: initialize with a closure

  /// Initialize with a computation task to be performed in the background
  ///
  /// - parameter qos:  the Quality-of-Service class at which the computation (and notifications) should be performed; defaults to the current QoS.
  /// - parameter task: the computation to be performed

  public convenience init(qos: DispatchQoS = DispatchQoS.current ?? .default, task: @escaping () throws -> Value)
  {
    let queue = DispatchQueue.global(qos: qos.qosClass)
    self.init(queue: queue, task: task)
  }

  /// Initialize with a computation task to be performed on the specified queue
  ///
  /// - parameter queue: the `DispatchQueue` on which the computation (and notifications) will be executed
  /// - parameter qos:   the Quality-of-Service class at which the computation should be performed; defaults to the QOS class of `queue`
  /// - parameter task:  the computation to be performed

  public init(queue: DispatchQueue, qos: DispatchQoS? = nil, task: @escaping () throws -> Value)
  {
    self.queue = queue
    source = nil
    determination = nil
    waiters.initialize(nil)
    stateid.initialize(1)

    queue.async {
      do {
        let value = try task()
        self.determine(value)
      }
      catch {
        self.determine(error)
      }
    }
  }

  // MARK: initialize with a result, value or error

  /// Initialize to an already determined state
  ///
  /// - parameter qos: the Quality-of-Service class at which the notifications should be performed.
  /// - parameter value: the value of this `Deferred`

  public convenience init(qos: DispatchQoS = DispatchQoS.current ?? .default, value: Value)
  {
    let queue = DispatchQueue.global(qos: qos.qosClass)
    self.init(queue: queue, value: value)
  }

  /// Initialize to an already determined state
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed
  /// - parameter value: the value of this `Deferred`

  public convenience init(queue: DispatchQueue, value: Value)
  {
    self.init(queue: queue, result: Determined(value))
  }

  /// Initialize with an Error
  ///
  /// - parameter qos: the Quality-of-Service class at which the notifications should be performed.
  /// - parameter error: the error state of this `Deferred`

  public convenience init(qos: DispatchQoS = DispatchQoS.current ?? .default, error: Error)
  {
    let queue = DispatchQueue.global(qos: qos.qosClass)
    self.init(queue: queue, error: error)
  }

  /// Initialize with an Error
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed
  /// - parameter error: the error state of this `Deferred`

  public convenience init(queue: DispatchQueue, error: Error)
  {
    self.init(queue: queue, result: Determined(error))
  }

  // MARK: fileprivate methods

  /// Change the state of this `Deferred` from `.waiting` to `.executing`

  fileprivate func beginExecution()
  {
    if stateid.load(.relaxed) == 0 { stateid.store(1, .relaxed) }
  }

  /// Set the `Result` of this `Deferred` and dispatch all notifications for execution.
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter result: the intended `Result` to determine this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  fileprivate func determine(_ result: Determined<Value>) -> Bool
  {
    var current: Int32 = 1
    while !stateid.loadCAS(&current, 2, .weak, .relaxed, .relaxed)
    { // keep trying if another thread hasn't succeeded yet
      if current == 2
      { // another thread succeeded ahead of this one
        return false
      }
    }

    determination = result
    source = nil

    let waitQueue = waiters.swap(.determined, .acqrel)?.assumingMemoryBound(to: Waiter<Value>.self)
    // precondition(waitQueue != .determined)
    notifyWaiters(queue, waitQueue, result)

    // precondition(waiters.load() == .determined, "waiters.pointer has incorrect value \(String(describing: waiters.load()))")

    // The result is now available for the world
    return true
  }

  /// Set the `Result` of this `Deferred` and dispatch all notifications for execution.
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter determined: the determined value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.


  /// Set the value of this `Deferred` and dispatch all notifications for execution.
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  fileprivate func determine(_ value: Value) -> Bool
  {
    return determine(Determined(value))
  }

  /// Set this `Deferred` to an error and dispatch all notifications for execution.
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter error: the intended error for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  fileprivate func determine(_ error: Error) -> Bool
  {
    return determine(Determined(error))
  }

  // MARK: public interface

  /// Enqueue a closure to be performed asynchronously after this `Deferred` becomes determined.
  /// This operation is lock-free and thread-safe.
  /// Multiple threads can call this method at once; they will succeed in turn.
  /// If one or more thread enters a race to enqueue with `determine()`, as soon as `determine()` succeeds
  /// all current and subsequent attempts to enqueue will result in immediate dispatch of the task.
  /// Note that the enqueued closure will does not modify `task`, and will not extend the lifetime of `self`.
  ///
  /// - parameter qos:  the Quality-of-Service class at which this notification should execute; defaults to the QOS class of this `Deferred`'s queue.
  /// - parameter task: a closure to be executed after `self` becomes determined.

  open func enqueue(qos: DispatchQoS? = nil, task: @escaping (Determined<Value>) -> Void)
  {
    var waitQueue = waiters.load(.acquire)
    if waitQueue != .determined
    {
      let waiter = UnsafeMutablePointer<Waiter<Value>>.allocate(capacity: 1)
      waiter.initialize(to: Waiter(qos, task))

      repeat {
        waiter.pointee.next = waitQueue?.assumingMemoryBound(to: Waiter<Value>.self)
        if waiters.loadCAS(&waitQueue, UnsafeMutableRawPointer(waiter), .weak, .acqrel, .acquire)
        { // waiter is now enqueued; it will be deallocated at a later time by notifyWaiters()
          return
        }
      } while waitQueue != .determined

      // this Deferred has become determined; clean up
      waiter.deinitialize(count: 1)
      waiter.deallocate(capacity: 1)
    }

    // this Deferred is determined
    queue.async(qos: qos, execute: { [value = determination!] in task(value) })
  }

  /// Enqueue a notification to be performed asynchronously after this `Deferred` becomes determined.
  /// The enqueued closure will extend the lifetime of `self` until `task` completes.
  ///
  /// - parameter qos:  the Quality-of-Service class at which this notification should execute; defaults to the QOS class of this `Deferred`'s queue.
  /// - parameter task: a closure to be executed as a notification

  public func notify(qos: DispatchQoS? = nil, task: @escaping (Determined<Value>) -> Void)
  {
    enqueue(qos: qos, task: { value in withExtendedLifetime(self) { task(value) } })
  }

  /// Query the current state of this `Deferred`
  ///
  /// - returns: a `DeferredState` (`.waiting`, `.executing` or `.determined`)

  public var state: DeferredState {
    return (waiters.load(.acquire) != .determined) ?
      (stateid.load(.relaxed) == 0 ? .waiting : .executing ) :
      (determination!.isValue ? .succeeded : .errored)
  }

  /// Query whether this `Deferred` has been determined.
  ///
  /// - returns: wheither this `Deferred` has been determined.

  public var isDetermined: Bool {
    return waiters.load(.relaxed) == .determined
  }

  /// Attempt to cancel the current operation, and report on whether cancellation happened successfully.
  /// A successful cancellation will result in a `Deferred` equivalent as if it had been initialized as follows:
  /// ```
  /// Deferred<Value>(error: DeferredError.canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  open func cancel(_ reason: String = "") -> Bool
  {
    return determine(DeferredError.canceled(reason))
  }

  /// Get this `Deferred`'s `Determined` result, blocking if necessary until it exists.
  ///
  /// - returns: this `Deferred`'s determined result

  private var determined: Determined<Value> {
    if waiters.load(.acquire) != .determined
    {
      let s = DispatchSemaphore(value: 0)
      self.enqueue(qos: DispatchQoS.current) { _ in s.signal() }
      s.wait()
      _ = waiters.load(.acquire)
    }

    // this Deferred is determined
    return determination!
  }

  /// Get this `Deferred`'s value, blocking if necessary until it becomes determined.
  /// If the `Deferred` is determined with an `Error`, throw it.
  /// When called on a `Deferred` that is already determined, this call is non-blocking.
  /// When called on a `Deferred` that is not determined, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s determined value, or `nil`

  public func get() throws -> Value
  {
    return try determined.get()
  }

  @available(*, unavailable, message: "the isDetermined property provides a non-blocking check that can replace peek()")
  public func peek() -> Value? { return nil }

  /// Get this `Deferred`'s value, blocking if necessary until it becomes determined.
  /// If the `Deferred` is determined with an `Error`, return nil.
  /// In either case, this property will block until `Deferred` is determined.
  ///
  /// - returns: this `Deferred`'s determined value, or `nil`

  public var value: Value? {
    return determined.value
  }

  /// Get this `Deferred`'s error, blocking if necessary until it becomes determined.
  /// If the `Deferred` is determined with a `Value`, return nil.
  /// In either case, this property will block until `Deferred` is determined.
  ///
  /// - returns: this `Deferred`'s determined value, or `nil`

  public var error: Error? {
    return determined.error
  }

  /// Get the quality-of-service class of this `Deferred`'s queue
  /// - returns: the quality-of-service class of this `Deferred`'s queue

  public var qos: DispatchQoS { return self.queue.qos }

  /// Set the queue to be used for future notifications
  /// - parameter queue: the queue to be used by the returned `Deferred`
  /// - returns: a new `Deferred` whose notifications will execute on `queue`

  public func enqueuing(on queue: DispatchQueue) -> Deferred
  {
    if waiters.load(.acquire) == .determined
    {
      return Deferred(queue: queue, result: determination!)
    }

    let beginExecution = stateid.load(.relaxed) != 0
    let deferred = Deferred(queue: queue, source: self, beginExecution: beginExecution)
    self.enqueue(qos: queue.qos, task: { [weak deferred] in deferred?.determine($0) })
    return deferred
  }

  @available(*, unavailable, renamed: "enqueuing")
  public func notifying(on queue: DispatchQueue) -> Deferred { return enqueuing(on: queue) }

  /// Set the quality-of-service to use for future notifications.
  /// The returned `Deferred` will issue notifications on a concurrent queue at the specified quality-of-service class.
  /// - parameter qos: the quality-of-service class to be used by the returned `Deferred`
  /// - returns: a new `Deferred` whose notifications will run at quality-of-service `qos`

  public func enqueuing(at qos: DispatchQoS, serially: Bool = false) -> Deferred
  {
    let queue = DispatchQueue(label: "deferred", qos: qos, attributes: serially ? [] : .concurrent)
    return enqueuing(on: queue)
  }

  @available(*, unavailable, renamed: "enqueuing")
  public func notifying(at qos: DispatchQoS, serially: Bool = false) -> Deferred { return enqueuing(at: qos, serially: serially) }
}


/// A mapped `Deferred`

internal final class Mapped<Value>: Deferred<Value>
{
  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `map`
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the QOS class of this `Deferred`'s queue.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init<U>(qos: DispatchQoS?, source: Deferred<U>, transform: @escaping (U) throws -> Value)
  {
    super.init(source: source)

    source.enqueue(qos: qos) {
      [weak self] value in
      guard let this = self else { return }
      if this.isDetermined { return }
      this.beginExecution()
      do {
        let value = try value.get()
        let transformed = try transform(value)
        this.determine(transformed)
      }
      catch {
        this.determine(error)
      }
    }
  }
}

internal final class Bind<Value>: Deferred<Value>
{
  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `flatMap`
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the QOS class of this `Deferred`'s queue.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init<U>(qos: DispatchQoS?, source: Deferred<U>, transform: @escaping (U) -> Deferred<Value>)
  {
    super.init(source: source)

    source.enqueue(qos: qos) {
      [weak self] value in
      guard let this = self else { return }
      if this.isDetermined { return }
      this.beginExecution()
      do {
        let value = try value.get()
        transform(value).notify(qos: qos) {
          [weak this] transformed in
          this?.determine(transformed)
        }
      }
      catch {
        this.determine(error) // an error here means this `Deferred` has been canceled.
      }
    }
  }

  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `recover` -- flatMap for the `ErrorType` path.
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the QOS class of this `Deferred`'s queue.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init(qos: DispatchQoS?, source: Deferred<Value>, transform: @escaping (Error) -> Deferred<Value>)
  {
    super.init(source: source)

    source.enqueue(qos: qos) {
      [weak self] determined in
      guard let this = self else { return }
      if this.isDetermined { return }
      this.beginExecution()
      if let error = determined.error
      {
        transform(error).notify(qos: qos) {
          [weak this] transformed in
          this?.determine(transformed)
        }
      }
      else
      {
        this.determine(determined)
      }
    }
  }
}

/// A `Deferred` that applies a `Deferred` transform onto its input

internal final class Applicator<Value>: Deferred<Value>
{
  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `apply`
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the QOS class of this `Deferred`'s queue.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init<U>(qos: DispatchQoS?, source: Deferred<U>, transform: Deferred<(U) throws -> Value>)
  {
    super.init(source: source)

    source.enqueue(qos: qos) {
      [weak self] value in
      guard let this = self else { return }
      if this.isDetermined { return }
      do {
        let value = try value.get()
        transform.notify(qos: qos) {
          [weak this] transform in
          guard let this = this else { return }
          if this.isDetermined { return }
          this.beginExecution()
          do {
            let transform = try transform.get()
            let transformed = try transform(value)
            this.determine(transformed)
          }
          catch {
            this.determine(error)
          }
        }
      }
      catch {
        this.determine(error)
      }
    }
  }
}

/// A `Deferred` with a time-delay

internal final class Delayed<Value>: Deferred<Value>
{
  /// Initialize with a `Deferred` source and a time after which this `Deferred` may become determined.
  /// The determination could be delayed further if `source` has not become determined yet,
  /// but it will not happen earlier than the time referred to by `until`.
  /// This constructor is used by `delay`
  ///
  /// - parameter source: the `Deferred` whose value should be delayed
  /// - parameter until:  the target time until which the determination of this `Deferred` will be delayed

  init(source: Deferred<Value>, until time: DispatchTime)
  {
    super.init(source: source)

    source.enqueue {
      [weak self] value in
      guard let this = self else { return }
      if this.isDetermined { return }

      if value.isError
      {
        this.determine(value)
        return
      }

      this.beginExecution()
      if time == .distantFuture { return }
      // enqueue block only if can get executed
      if time > .now()
      {
        this.queue.asyncAfter(deadline: time) {
          [weak this] in
          this?.determine(value)
        }
      }
      else
      {
        this.determine(value)
      }
    }
  }
}

/// A `Deferred` to be determined (`TBD`) manually.

open class TBD<Value>: Deferred<Value>
{
  /// Initialize an undetermined `Deferred`, `TBD`.
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed

  public override init(queue: DispatchQueue)
  {
    super.init(queue: queue)
  }

  /// Initialize an undetermined `Deferred`, `TBD`.
  ///
  /// - parameter qos: the Quality-of-Service class at which the notifications should be performed; defaults to the current quality-of-service class.

  public convenience init(qos: DispatchQoS = DispatchQoS.current ?? .default)
  {
    let queue = DispatchQueue.global(qos: qos.qosClass)
    self.init(queue: queue)
  }

  /// Set the `Result` of this `Deferred` and dispatch all notifications for execution.
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter result: the determined value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  public override func determine(_ result: Determined<Value>) -> Bool
  {
    return super.determine(result)
  }

  /// Set the value of this `Deferred`  and dispatch all notifications for execution.
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  public override func determine(_ value: Value) -> Bool
  {
    return super.determine(value)
  }

  /// Set this `Deferred` to an error and dispatch all notifications for execution.
  /// Note that a `Deferred` can only be determined once.
  /// On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter error: the intended error for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  public override func determine(_ error: Error) -> Bool
  {
    return super.determine(error)
  }

  /// Change the state of this `TBD` from `.waiting` to `.executing`

  open override func beginExecution()
  {
    super.beginExecution()
  }
}
