//
//  deferred.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-09.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

/// The possible states of a `Deferred`.
///
/// Must be a top-level type because Deferred is generic.

public enum DeferredState: Int32 { case waiting = 0, executing = 1, determined = 2 }
private let transientState = Int32.max

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

public class Deferred<Value>
{
  private var r: Result<Value>

  // Swift does not have a facility to read and write enum values atomically.
  // To get around this, we use a raw `Int32` value as a proxy for the enum value.

  private var currentState: Int32

  private let queue: DispatchQueue
  private var waiters: UnsafeMutablePointer<Waiter<Value>>? = nil

  deinit
  {
    WaitQueue.dealloc(waiters)
  }

  // MARK: designated initializers

  private init(queue: DispatchQueue)
  {
    r = Result()
    self.queue = queue
    currentState = DeferredState.waiting.rawValue
  }

  /// Initialize to an already determined state
  ///
  /// - parameter queue:  the dispatch queue upon which to execute future notifications for this `Deferred`
  /// - parameter result: the result of this `Deferred`

  public init(queue: DispatchQueue, result: Result<Value>)
  {
    r = result
    self.queue = queue
    currentState = DeferredState.determined.rawValue
  }

  // MARK: initialize with a closure

  /// Initialize with a computation task to be performed in the background, at the current quality of service
  ///
  /// - parameter task: the computation to be performed

  public convenience init(task: () throws -> Value)
  { // FIXME: verify that qos is correct
    let queue = DispatchQueue.global(qos: DispatchQoS.QoSClass(rawValue: qos_class_self()) ?? .default)
    self.dynamicType.init(queue: queue, task: task)
    // was queue: dispatch_get_global_queue(qos_class_self(), 0)
  }

  /// Initialize with a computation task to be performed in the background
  ///
  /// - parameter qos:  the Quality-of-Service class at which the computation (and notifications) should be performed
  /// - parameter task: the computation to be performed

  public convenience init(qos: DispatchQoS, task: () throws -> Value)
  { // FIXME: get queue at intended qos
    self.dynamicType.init(queue: DispatchQueue.global(qos: qos.qosClass), task: task)
    // was queue: dispatch_get_global_queue(qos, 0)
  }

  /// Initialize with a computation task to be performed on the specified queue
  ///
  /// - parameter queue: the `DispatchQueue` onto which the computation (and notifications) will be enqueued
  /// - parameter task:  the computation to be performed

  public convenience init(queue: DispatchQueue, qos: DispatchQoS = .unspecified, task: () throws -> Value)
  {
    self.dynamicType.init(queue: queue)

    let closure = {
      let result = Result { _ in try task() }
      self.determine(result) // an error here means this `Deferred` has been canceled.
    }

    currentState = DeferredState.executing.rawValue
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
  { // FIXME: get queue at intended qos
    self.dynamicType.init(queue: DispatchQueue.global(qos: qos.qosClass), result: result)
    // was queue: dispatch_get_global_queue(qos, 0)
  }

  /// Initialize to an already determined state, with a queue at the current quality-of-service class.
  ///
  /// - parameter result: the result of this `Deferred`

  public convenience init(_ result: Result<Value>)
  {
    self.dynamicType.init(queue: DispatchQueue.global(), result: result)
  }

  /// Initialize to an already determined state, with a queue at the current quality-of-service class.
  ///
  /// - parameter value: the value of this `Deferred`'s `Result`

  public convenience init(value: Value)
  {
    self.dynamicType.init(Result.value(value))
  }

  /// Initialize to an already determined state, with a queue at the current quality-of-service class.
  ///
  /// - parameter error: the error state of this `Deferred`'s `Result`

  public convenience init(error: Error)
  {
    self.dynamicType.init(Result.error(error))
  }

  // MARK: private methods

  /// Change the state of this `Deferred` from `.waiting` to `.executing`

  private func beginExecution()
  {
    CAS(current: DeferredState.waiting.rawValue, new: DeferredState.executing.rawValue, target: &currentState)
  }

  /// Set the `Result` of this `Deferred`, change its state to `DeferredState.determined`,
  /// enqueue all notifications on the dispatch_queue, then return `true`.
  /// Note that a `Deferred` can only be determined once. On subsequent calls, `determine` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter result: the intended `Result` to determine this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  private func determine(_ result: Result<Value>) -> Bool
  {
    // A turnstile to ensure only one thread can succeed
    while true
    { // Allow multiple tries in case another thread concurrently switches state from .waiting to .executing
      let initialState = currentState
      if initialState >= DeferredState.determined.rawValue
      { // this thread will not succeed
        return false
      }
      if CAS(current: initialState, new: transientState, target: &currentState)
      { // this thread has succeeded; change `r` and enqueue notification blocks.
        break
      }
    }

    r = result
    currentState = DeferredState.determined.rawValue
    OSMemoryBarrier()

    while true
    {
      let waitQueue = waiters
      if CAS(current: waitQueue, new: nil, target: &waiters)
      {
        // only this thread has the pointer `waitQueue`.
        WaitQueue.notifyAll(queue, waitQueue, result)
        break
      }
    }

    // The result is now available for the world
    return true
  }

  /// Enqueue a Waiter to this Deferred's list of Waiters.
  /// This operation is lock-free and thread-safe.
  /// Multiple threads can attempt to enqueue at once; they will succeed in turn and return true.
  /// If one or more thread enters a race to enqueue with `determine()`, as soon as `determine()` succeeds
  /// all current and subsequent attempts to enqueue will fail and return false.
  ///
  /// A failure to enqueue indicates that this `Deferred` is now determined and can now make its Result available.
  ///
  /// - parameter waiter: A `Waiter` to enqueue
  /// - returns: whether enqueueing was successful.

  private func enqueue(_ waiter: UnsafeMutablePointer<Waiter<Value>>) -> Bool
  {
    while true
    {
      let waitQueue = waiters
      waiter.pointee.next = waitQueue
      if syncread(&currentState) != DeferredState.determined.rawValue
      {
        if CAS(current: waitQueue, new: waiter, target: &waiters)
        { // waiter is now enqueued; it will be deallocated at a later time by WaitQueue.notifyAll()
          return true
        }
      }
      else
      { // This Deferred has become determined; bail
        waiter.deinitialize()
        waiter.deallocate(capacity: 1)
        break
      }
    }
    return false
  }

  // MARK: public interface

  /// Enqueue a closure to be performed asynchronously after this `Deferred` becomes determined
  ///
  /// - parameter task:  the closure to be enqueued

  public func notify(qos: DispatchQoS = .unspecified, task: (Result<Value>) -> Void)
  {
    if currentState != DeferredState.determined.rawValue
    {
      let waiter = UnsafeMutablePointer<Waiter<Value>>.allocate(capacity: 1)
      waiter.initialize(to: Waiter(qos, task))

      // waiter will be deallocated later
      if enqueue(waiter)
      {
        return
      }
    }

    let closure = { [ result = self.r ] in task(result) }

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

  public var state: DeferredState { return DeferredState(rawValue: currentState) ?? .executing }

  /// Query whether this `Deferred` has been determined.
  ///
  /// - returns: wheither this `Deferred` has been determined.

  public var isDetermined: Bool { return currentState == DeferredState.determined.rawValue }

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
    if currentState != DeferredState.determined.rawValue
    {
      return nil
    }
    return r
  }

  /// Get this `Deferred`'s value as a `Result`, blocking if necessary until it becomes determined.
  ///
  /// - returns: this `Deferred`'s determined result

  public var result: Result<Value> {
    if currentState != DeferredState.determined.rawValue
    {
      let s = DispatchSemaphore(value: 0)
      self.notify() { _ in s.signal() }
      // was: self.notify(qos: qos_class_self())
      s.wait()
    }

    return r
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
    if currentState == DeferredState.determined.rawValue
    {
      return Deferred(queue: queue, result: self.r)
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

  init<U>(qos: DispatchQoS, source: Deferred<U>, transform: (U) throws -> Value)
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

  init<U>(qos: DispatchQoS, source: Deferred<U>, transform: (U) -> Result<Value>)
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

  init<U>(qos: DispatchQoS, source: Deferred<U>, transform: (U) -> Deferred<Value>)
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

  init(qos: DispatchQoS, source: Deferred<Value>, transform: (Error) -> Deferred<Value>)
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

public class TBD<Value>: Deferred<Value>
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

  public convenience init(qos: DispatchQoS = .unspecified)
  { // FIXME: should default to qos_class_self()
    // FIXME: get queue at intended qos
    self.dynamicType.init(queue: DispatchQueue.global())
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
