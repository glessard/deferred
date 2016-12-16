//
//  deferred.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-09.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

#if SWIFT_PACKAGE
  import utilities
  import Atomics
#endif

/// The possible states of a `Deferred`.
///
/// Must be a top-level type because Deferred is generic.

public enum DeferredState { case waiting, executing, determined }

/// An asynchronous computation.
///
/// A `Deferred` starts out undetermined, in the `.waiting` state.
/// It may then enter the `.executing` state, and will eventually become `.determined`.
/// Once it is `.determined`, it is ready to supply a result.
///
/// The `result` property will return the result, blocking until it becomes determined.
/// If the result is ready when `result` is called, it will return immediately.
///
/// A closure supplied to the `notify` method will be called after the `Deferred` has become determined.

open // would prefer "public", but an "open" class can only descend from another "open" class.
class Deferred<Value>
{
  fileprivate let queue: DispatchQueue

  private var resultp: AtomicMutablePointer<Result<Value>>
  private var waiters: AtomicMutablePointer<Waiter<Value>>
  private var started: AtomicInt32

  deinit
  {
    WaitQueue.dealloc(waiters.pointer)
    if let p = resultp.pointer
    {
      p.deinitialize(count: 1)
      p.deallocate(capacity: 1)
    }
  }

  // MARK: designated initializers

  fileprivate init(queue: DispatchQueue)
  {
    self.resultp = AtomicMutablePointer(nil)
    self.waiters = AtomicMutablePointer(nil)
    self.started = AtomicInt32(0)

    self.queue = queue
  }

  /// Initialize to an already determined state
  ///
  /// - parameter queue:  the dispatch queue upon which to execute future notifications for this `Deferred`
  /// - parameter result: the result of this `Deferred`

  public init(queue: DispatchQueue, result: Result<Value>)
  {
    let p = UnsafeMutablePointer<Result<Value>>.allocate(capacity: 1)
    p.initialize(to: result)

    self.resultp = AtomicMutablePointer(p)
    self.waiters = AtomicMutablePointer(nil)
    self.started = AtomicInt32(1)

    self.queue = queue
  }

  // MARK: initialize with a closure

  /// Initialize with a computation task to be performed in the background, at the current quality of service
  ///
  /// - parameter task: the computation to be performed

  public convenience init(task: @escaping () throws -> Value)
  {
    let queue = DispatchQueue.global(qos: DispatchQoS.QoSClass.current(fallback: .default))
    self.init(queue: queue, task: task)
    // was queue: dispatch_get_global_queue(qos_class_self(), 0)
  }

  /// Initialize with a computation task to be performed in the background
  ///
  /// - parameter qos:  the Quality-of-Service class at which the computation (and notifications) should be performed
  /// - parameter task: the computation to be performed

  public convenience init(qos: DispatchQoS, task: @escaping () throws -> Value)
  {
    self.init(queue: DispatchQueue.global(qos: qos.qosClass), task: task)
    // was queue: dispatch_get_global_queue(qos, 0)
  }

  /// Initialize with a computation task to be performed on the specified queue
  ///
  /// - parameter queue: the `DispatchQueue` onto which the computation (and notifications) will be enqueued
  /// - parameter task:  the computation to be performed

  public convenience init(queue: DispatchQueue, qos: DispatchQoS = .unspecified, task: @escaping () throws -> Value)
  {
    self.init(queue: queue)

    let closure = {
      let result = Result { _ in try task() }
      self.determine(result) // an error here means this `Deferred` has been canceled.
    }

    self.started = AtomicInt32(1)

    if qos == .unspecified
    {
      queue.async(execute: closure)
    }
    else
    {
      queue.async(qos: qos, flags: [.enforceQoS], execute: closure)
    }
  }

  // MARK: initialize with a result, value or error

  /// Initialize to an already determined state
  ///
  /// - parameter qos:    the quality of service of the concurrent queue upon which to execute future notifications for this `Deferred`
  ///                     `qos` defaults to the currently-executing quality-of-service class.
  /// - parameter result: the result of this `Deferred`

  public convenience init(qos: DispatchQoS, result: Result<Value>)
  {
    self.init(queue: DispatchQueue.global(qos: qos.qosClass), result: result)
    // was queue: dispatch_get_global_queue(qos, 0)
  }

  /// Initialize to an already determined state, with a queue at the current quality-of-service class.
  ///
  /// - parameter result: the result of this `Deferred`

  public convenience init(_ result: Result<Value>)
  {
    self.init(queue: DispatchQueue.global(), result: result)
  }

  /// Initialize to an already determined state, with a queue at the current quality-of-service class.
  ///
  /// - parameter value: the value of this `Deferred`'s `Result`

  public convenience init(value: Value)
  {
    self.init(Result.value(value))
  }

  /// Initialize to an already determined state, with a queue at the current quality-of-service class.
  ///
  /// - parameter error: the error state of this `Deferred`'s `Result`

  public convenience init(error: Error)
  {
    self.init(Result.error(error))
  }

  // MARK: fileprivate methods

  /// Change the state of this `Deferred` from `.waiting` to `.executing`

  fileprivate func beginExecution()
  {
    if started.value == 0 { started.store(1) }
  }

  /// Set the `Result` of this `Deferred`, change its state to `DeferredState.determined`,
  /// enqueue all notifications on the DispatchQueue, then return `true`.
  /// Note that a `Deferred` can only be determined once. On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter result: the intended `Result` to determine this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  fileprivate func determine(_ result: Result<Value>) -> Bool
  {
    guard resultp.pointer == nil
    else { // this Deferred is already determined
      return false
    }

    // optimistically allocate storage for result
    let p = UnsafeMutablePointer<Result<Value>>.allocate(capacity: 1)
    p.initialize(to: result)

    while true
    {
      if resultp.CAS(current: nil, future: p, orderSuccess: .release, orderFailure: .relaxed)
      {
        break
      }

      if resultp.pointer != nil
      { // another thread succeeded ahead of this one; clean up
        assert(resultp.pointer != p)
        p.deinitialize(count: 1)
        p.deallocate(capacity: 1)
        return false
      }
    }

    let waitQueue = waiters.swap(nil, order: .consume)
    WaitQueue.notifyAll(queue, waitQueue, result)

    // The result is now available for the world
    return true
  }

  // MARK: public interface

  /// Enqueue a closure to be performed asynchronously after this `Deferred` becomes determined
  /// This operation is lock-free and thread-safe.
  /// Multiple threads can call this method at once; they will succeed in turn.
  /// If one or more thread enters a race to enqueue with `determine()`, as soon as `determine()` succeeds
  /// all current and subsequent attempts to enqueue will result in immediate dispatch of the task.
  ///
  /// - parameter task:  the closure to be enqueued

  public func notify(qos: DispatchQoS = .unspecified, task: @escaping (Result<Value>) -> Void)
  {
    var c = resultp.load(order: .consume)
    if c == nil
    {
      let waiter = UnsafeMutablePointer<Waiter<Value>>.allocate(capacity: 1)
      waiter.initialize(to: Waiter(qos, task))

      while true
      {
        let waitQueue = waiters.pointer
        waiter.pointee.next = waitQueue

        c = resultp.load(order: .consume)
        if c == nil
        {
          if waiters.CAS(current: waitQueue, future: waiter, orderSuccess: .release, orderFailure: .relaxed)
          { // waiter is now enqueued; it will be deallocated at a later time by WaitQueue.notifyAll()
            return
          }
        }
        else
        { // this Deferred has become determined; clean up
          waiter.deinitialize(count: 1)
          waiter.deallocate(capacity: 1)
          break
        }
      }
    }

    // this Deferred is determined
    guard let result = c?.pointee else { fatalError("Pointer should be non-null in \(#function)") }
    let closure = { task(result) }

    if qos == .unspecified
    {
      queue.async(execute: closure)
    }
    else
    {
      queue.async(qos: qos, flags: [.enforceQoS], execute: closure)
    }
  }

  /// Query the current state of this `Deferred`
  ///
  /// - returns: a `DeferredState` (`.waiting`, `.executing` or `.determined`)

  public var state: DeferredState {
    if resultp.pointer == nil
    {
      if started.value == 0
      {
        return .waiting
      }
      return .executing
    }
    return .determined
  }

  /// Query whether this `Deferred` has been determined.
  ///
  /// - returns: wheither this `Deferred` has been determined.

  public var isDetermined: Bool {
    return resultp.pointer != nil
  }

  /// Attempt to cancel the current operation, and report on whether cancellation happened successfully.
  /// A successful cancellation will determine result in a `Deferred` equivalent as if it had been initialized as follows:
  /// ```
  /// Deferred<Value>(error: DeferredError.Canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  public func cancel(_ reason: String = "") -> Bool
  {
    return determine(Result.error(DeferredError.canceled(reason)))
  }

  /// Get this `Deferred` value if it has been determined, `nil` otherwise.
  /// (This call does not block)
  ///
  /// - returns: this `Deferred`'s value, or `nil`

  public func peek() -> Result<Value>?
  {
    if let p = resultp.pointer
    {
      return p.pointee
    }
    return nil
  }

  /// Get this `Deferred`'s value as a `Result`, blocking if necessary until it becomes determined.
  ///
  /// - returns: this `Deferred`'s determined result

  public var result: Result<Value> {
    var c = resultp.load(order: .consume)
    if c == nil
    {
      let s = DispatchSemaphore(value: 0)
      let qos = DispatchQoS.current(fallback: .unspecified)
      self.notify(qos: qos) { _ in s.signal() }
      // was: self.notify(qos: qos_class_self())
      s.wait()

      c = resultp.load(order: .sequential)
    }

    guard let p = c else { fatalError() }
    return p.pointee
  }

  /// Get this `Deferred` value, blocking if necessary until it becomes determined.
  /// If the `Deferred` is determined by a `Result` in the `.error` state, return nil.
  /// In either case, this property will block until `Deferred` is determined.
  ///
  /// - returns: this `Deferred`'s determined value, or `nil`

  public var value: Value? {
    if case let .value(v) = result { return v }
    return nil
  }

  /// Get this `Deferred` value, blocking if necessary until it becomes determined.
  /// If the `Deferred` is determined by a `Result` in the `.error` state, return nil.
  /// In either case, this property will block until `Deferred` is determined.
  ///
  /// - returns: this `Deferred`'s determined value, or `nil`

  public var error: Error? {
    if case let .error(e) = result { return e }
    return nil
  }

  /// Get the quality-of-service class of this `Deferred`'s queue
  /// - returns: the quality-of-service class of this `Deferred`'s queue

  public var qos: DispatchQoS { return self.queue.qos }

  /// Set the queue to be used for future notifications
  /// - parameter queue: the queue to be used by the returned `Deferred`
  /// - returns: a new `Deferred` whose notifications will run on `queue`

  public func notifying(on queue: DispatchQueue) -> Deferred
  {
    if let p = resultp.load(order: .consume)
    {
      return Deferred(queue: queue, result: p.pointee)
    }

    let deferred = Deferred(queue: queue)
    self.notify(qos: queue.qos, task: { deferred.determine($0) })
    return deferred
  }

  /// Set the quality-of-service to use for future notifications.
  /// The returned `Deferred` will issue notifications on a concurrent queue at the specified quality-of-service class.
  /// - parameter qos: the quality-of-service class to be used by the returned `Deferred`
  /// - returns: a new `Deferred` whose notifications will run at quality-of-service `qos`

  public func notifying(at qos: DispatchQoS, serially: Bool = false) -> Deferred
  {
    if serially
    {
      return notifying(on: DispatchQueue(label: "deferred-serial", qos: qos))
    }

    return notifying(on: DispatchQueue.global(qos: qos.qosClass))
  }
}


/// A mapped `Deferred`

internal final class Mapped<Value>: Deferred<Value>
{
  /// Initialize to an already determined state, and copy the queue reference from another `Deferred`
  ///
  /// - parameter source: a `Deferred` whose dispatch queue shoud be used to enqueue future notifications for this `Deferred`
  /// - parameter result: the result of this `Deferred`

  init<U>(source: Deferred<U>, result: Result<Value>)
  {
    super.init(queue: source.queue, result: result)
  }

  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `map`
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init<U>(qos: DispatchQoS, source: Deferred<U>, transform: @escaping (U) throws -> Value)
  {
    super.init(queue: source.queue)

    source.notify(qos: qos) {
      result in
      if self.isDetermined { return }
      self.beginExecution()
      let transformed = result.map(transform)
      self.determine(transformed) // an error here means this `Deferred` has been canceled.
    }
  }

  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by the version of `map` that uses a transform to a `Result`.
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init<U>(qos: DispatchQoS, source: Deferred<U>, transform: @escaping (U) -> Result<Value>)
  {
    super.init(queue: source.queue)

    source.notify(qos: qos) {
      result in
      if self.isDetermined { return }
      self.beginExecution()
      let transformed = result.flatMap(transform)
      self.determine(transformed) // an error here means this `Deferred` has been canceled.
    }
  }
}

internal final class Bind<Value>: Deferred<Value>
{
  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `flatMap`
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init<U>(qos: DispatchQoS, source: Deferred<U>, transform: @escaping (U) -> Deferred<Value>)
  {
    super.init(queue: source.queue)

    source.notify(qos: qos) {
      result in
      if self.isDetermined { return }
      self.beginExecution()
      switch result
      {
      case .value(let value):
        transform(value).notify(qos: qos) {
          transformed in
          self.determine(transformed) // an error here means this `Deferred` has been canceled.
        }

      case .error(let error):
        self.determine(Result.error(error)) // an error here means this `Deferred` has been canceled.
      }
    }
  }

  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `recover` -- flatMap for the `ErrorType` path.
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init(qos: DispatchQoS, source: Deferred<Value>, transform: @escaping (Error) -> Deferred<Value>)
  {
    super.init(queue: source.queue)

    source.notify(qos: qos) {
      result in
      if self.isDetermined { return }
      self.beginExecution()
      switch result
      {
      case .value:
        self.determine(result)

      case .error(let error):
        transform(error).notify(qos: qos) {
          transformed in
          self.determine(transformed)
        }
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
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init<U>(qos: DispatchQoS, source: Deferred<U>, transform: Deferred<(U) -> Result<Value>>)
  {
    super.init(queue: source.queue)

    source.notify(qos: qos) {
      result in
      if self.isDetermined { return }
      switch result
      {
      case .value:
        transform.notifying(on: self.queue).notify(qos: qos) {
          transform in
          if self.isDetermined { return }
          self.beginExecution()
          let transformed = result.apply(transform)
          self.determine(transformed) // an error here means this `Deferred` has been canceled.
        }

      case .error(let error):
        self.beginExecution()
        self.determine(Result.error(error)) // an error here means this `Deferred` has been canceled.
      }
    }
  }

  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `apply`
  ///
  /// - parameter queue:     the `DispatchQueue` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init<U>(qos: DispatchQoS, source: Deferred<U>, transform: Deferred<(U) throws -> Value>)
  {
    super.init(queue: source.queue)

    source.notify(qos: qos) {
      result in
      if self.isDetermined { return }
      switch result
      {
      case .value:
        transform.notifying(on: self.queue).notify(qos: qos) {
          transform in
          if self.isDetermined { return }
          self.beginExecution()
          let transformed = result.apply(transform)
          self.determine(transformed) // an error here means this `Deferred` has been canceled.
        }

      case .error(let error):
        self.beginExecution()
        self.determine(Result.error(error)) // an error here means this `Deferred` has been canceled.
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
    super.init(queue: source.queue)

    source.notify {
      result in
      if self.isDetermined { return }

      if case .value = result, time > DispatchTime.now()
      {
        self.beginExecution()
        self.queue.asyncAfter(deadline: time) { self.determine(result) }
      }
      else
      {
        self.determine(result) // an error here means this `Deferred` has been canceled.
      }
    }
  }
}

/// A `Deferred` which can time out

internal final class Timeout<Value>: Deferred<Value>
{
  /// Initialized with a `Deferred` source and the maximum number of nanoseconds we should wait for its result.
  /// If `source` does not become determined before the timeout expires, the new `Deferred` will be canceled.
  /// The new `Deferred` will use the same queue as the source.
  /// This constructor is used by `timeout`
  ///
  /// - parameter source: the `Deferred` whose value should be subjected to a timeout.
  /// - parameter timeout: maximum number of nanoseconds before timeout.
  /// - parameter reason: the reason for the cancelation if the operation times out.

  init(source: Deferred<Value>, deadline: DispatchTime, reason: String)
  {
    super.init(queue: source.queue)
    queue.asyncAfter(deadline: deadline) { self.cancel(reason) }
    source.notify { self.determine($0) } // an error here means this `Deferred` was canceled or has timed out.
  }
}

/// A `Deferred` to be determined (`TBD`) manually.

open class TBD<Value>: Deferred<Value>
{
  /// Initialize an undetermined `Deferred`, `TBD`.
  ///
  /// - parameter queue: the queue to be used when sending result notifications

  public override init(queue: DispatchQueue)
  {
    super.init(queue: queue)
  }

  /// Initialize an undetermined `Deferred`, `TBD`.
  ///
  /// - parameter qos: the quality of service to be used when sending result notifications; defaults to the current quality-of-service class.

  public convenience init(qos: DispatchQoS = DispatchQoS.current())
  {
    self.init(queue: DispatchQueue.global(qos: qos.qosClass))
  }

  /// Set the value of this `Deferred` and change its state to `DeferredState.determined`
  /// Note that a `Deferred` can only be determined once. On subsequent calls, `determine` will throw an `AlreadyDetermined` error.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - throws: `DeferredError.AlreadyDetermined` if the `Deferred` was already determined upon calling this method.

  public func determine(_ value: Value) throws
  {
    try determine(Result.value(value), place: #function)
  }

  /// Set this `Deferred` to an error and change its state to `DeferredState.determined`
  /// Note that a `Deferred` can only be determined once. On subsequent calls, `determine` will throw an `AlreadyDetermined` error.
  ///
  /// - parameter error: the intended error for this `Deferred`
  /// - throws: `DeferredError.AlreadyDetermined` if the `Deferred` was already determined upon calling this method.

  public func determine(_ error: Error) throws
  {
    try determine(Result.error(error), place: #function)
  }

  /// Set the `Result` of this `Deferred` and change its state to `DeferredState.determined`
  /// Note that a `Deferred` can only be determined once. On subsequent calls, `determine` will throw an `AlreadyDetermined` error.
  ///
  /// - parameter result: the intended `Result` for this `Deferred`
  /// - throws: `DeferredError.AlreadyDetermined` if the `Deferred` was already determined upon calling this method.

  public func determine(_ result: Result<Value>) throws
  {
    try determine(result, place: #function)
  }

  private func determine(_ result: Result<Value>, place: String) throws
  {
    guard super.determine(result) else { throw DeferredError.alreadyDetermined(place) }
  }

  /// Change the state of this `TBD` from `.waiting` to `.executing`

  public override func beginExecution()
  {
    super.beginExecution()
  }
}
