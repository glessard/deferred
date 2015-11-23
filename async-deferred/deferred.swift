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

public enum DeferredState: Int32 { case Waiting = 0, Executing = 1, Determined = 2 }
private let transientState = Int32.max

/// An asynchronous computation.
///
/// A `Deferred` starts out undetermined, in the `.Waiting` state.
/// It may then enter the `.Executing` state, and will eventually become `.Determined`.
/// Once it is `.Determined`, it is ready to supply a result.
///
/// The `result` property will return the result, blocking until it becomes determined.
/// If the result is ready when `result` is called, it will return immediately.
///
/// A closure supplied to the `notify` method will be called after the `Deferred` has become determined.

public class Deferred<T>
{
  private var r: Result<T>

  // Swift does not have a facility to read and write enum values atomically.
  // To get around this, we use a raw `Int32` value as a proxy for the enum value.

  private var currentState: Int32

  private let queue: dispatch_queue_t
  private var waiters: UnsafeMutablePointer<Waiter> = nil

  deinit
  {
    WaitQueue.dealloc(waiters)
  }

  // MARK: designated initializers

  private init(_ queue: dispatch_queue_t)
  {
    r = Result()
    self.queue = queue
    currentState = DeferredState.Waiting.rawValue
  }

  /// Initialize to an already determined state
  ///
  /// - parameter queue:  the dispatch queue upon which to execute future notifications for this `Deferred`
  /// - parameter result: the result of this `Deferred`

  public init(queue: dispatch_queue_t, result: Result<T>)
  {
    r = result
    self.queue = queue
    currentState = DeferredState.Determined.rawValue
  }

  // MARK: initialize with a closure

  /// Initialize with a computation task to be performed in the background, at the current quality of service
  ///
  /// - parameter task: the computation to be performed

  public convenience init(task: () throws -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  /// Initialize with a computation task to be performed in the background
  ///
  /// - parameter qos:  the Quality-of-Service class at which the computation (and notifications) should be performed
  /// - parameter task: the computation to be performed

  public convenience init(qos: qos_class_t, task: () throws -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  /// Initialize with a computation task to be performed on the specified queue
  ///
  /// - parameter queue: the `dispatch_queue_t` onto which the computation (and notifications) will be enqueued
  /// - parameter task:  the computation to be performed

  public convenience init(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, task: () throws -> T)
  {
    self.init(queue)

    let block = createBlock(qos) {
      let result = Result { _ in try task() }
      _ = try? self.determine(result) // an error here means this `Deferred` has been canceled.
    }

    currentState = DeferredState.Executing.rawValue
    dispatch_async(queue, block)
  }

  // MARK: initialize with a result, value or error

  /// Initialize to an already determined state
  ///
  /// - parameter qos:    the quality of service of the concurrent queue upon which to execute future notifications for this `Deferred`
  ///                     `qos` defaults to the currently-executing quality-of-service class.
  /// - parameter result: the result of this `Deferred`

  public convenience init(qos: qos_class_t, result: Result<T>)
  {
    self.init(queue: dispatch_get_global_queue(qos, 0), result: result)
  }

  /// Initialize to an already determined state, with a queue at the current quality-of-service class.
  ///
  /// - parameter result: the result of this `Deferred`

  public convenience init(_ result: Result<T>)
  {
    self.init(queue: dispatch_get_global_queue(qos_class_self(), 0), result: result)
  }

  /// Initialize to an already determined state, with a queue at the current quality-of-service class.
  ///
  /// - parameter value: the value of this `Deferred`'s `Result`

  public convenience init(value: T)
  {
    self.init(Result.Value(value))
  }

  /// Initialize to an already determined state, with a queue at the current quality-of-service class.
  ///
  /// - parameter error: the error state of this `Deferred`'s `Result`

  public convenience init(error: ErrorType)
  {
    self.init(Result.Error(error))
  }

  // MARK: private methods

  /// Change the state of this `Deferred` from `.Waiting` to `.Executing`

  private func beginExecution()
  {
    OSAtomicCompareAndSwap32Barrier(DeferredState.Waiting.rawValue, DeferredState.Executing.rawValue, &currentState)
  }

  /// Set the value of this `Deferred` and change its state to `DeferredState.Determined`
  /// Note that a `Deferred` can only be determined once. On subsequent calls, `setValue` will throw an `AlreadyDetermined` error.
  ///
  /// - parameter result: the intended `Result` to determine this `Deferred`
  /// - throws: `DeferredError.AlreadyDetermined` if the `Deferred` was already determined upon calling this method.

  private func determine(result: Result<T>) throws
  {
    // A turnstile to ensure only one thread can succeed
    while true
    { // Allow multiple tries in case another thread concurrently switches state from .Waiting to .Executing
      let initialState = currentState
      if initialState < DeferredState.Determined.rawValue
      {
        if OSAtomicCompareAndSwap32Barrier(initialState, transientState, &currentState) { break }
      }
      else
      {
        assert(currentState >= DeferredState.Determined.rawValue)
        throw DeferredError.AlreadyDetermined(__FUNCTION__)
      }
    }

    r = result

    guard OSAtomicCompareAndSwap32Barrier(transientState, DeferredState.Determined.rawValue, &currentState) else
    { // Getting here seems impossible, but try to handle it gracefully.
      throw DeferredError.CannotDetermine(__FUNCTION__)
    }

    while true
    {
      let waitQueue = waiters
      if CAS(waitQueue, nil, &waiters)
      {
        WaitQueue.notifyAll(queue, waitQueue)
        break
      }
    }

    // The result is now available for the world
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

  private func enqueue(waiter: UnsafeMutablePointer<Waiter>) -> Bool
  {
    while true
    {
      let tail = waiters
      waiter.memory.next = tail
      if syncread(&currentState) != DeferredState.Determined.rawValue
      {
        if CAS(tail, waiter, &waiters)
        { // waiter is now enqueued; it will be deallocated at a later time.
          return true
        }
      }
      else
      { // This Deferred has become determined; bail
        waiter.destroy()
        waiter.dealloc(1)
        return false
      }
    }
  }

  /// Take a (Result<T>) -> Void closure, and wrap it in a dispatch_block_t
  /// where this Deferred's Result is used as the input closure's parameter.
  ///
  /// - parameter qos: The QOS class to use for the new block (default is QOS_CLASS_UNSPECIFIED)
  /// - parameter task: The closure to be transformed
  /// - returns: a dispatch_block_t at the requested QOS class.

  private func createNotificationBlock(qos: qos_class_t = QOS_CLASS_UNSPECIFIED, task: (Result<T>) -> Void) -> dispatch_block_t
  {
    return createBlock(qos, block: { task(self.r) })
  }

  /// Take a () -> Void closure, and make it into a dispatch_block_t of an appropriate QOS class
  ///
  /// - parameter qos: The QOS class to use for the new block (default is QOS_CLASS_UNSPECIFIED)
  /// - parameter block: The closure to cast into a dispatch_block_t
  /// - returns: a dispatch_block_t at the requested QOS class.

  private func createBlock(qos: qos_class_t = QOS_CLASS_UNSPECIFIED, block: () -> Void) -> dispatch_block_t
  {
    let newBlock: dispatch_block_t
    if qos == QOS_CLASS_UNSPECIFIED
    {
      newBlock = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, block)
    }
    else
    {
      newBlock = dispatch_block_create_with_qos_class(DISPATCH_BLOCK_ENFORCE_QOS_CLASS, qos, 0, block)
    }
    return newBlock
  }

  // MARK: public interface

  /// Enqueue a computation to be performed upon the determination of this `Deferred`
  ///
  /// - parameter block: the computation to be enqueued, as a `dispatch_block_t`.

  public final func notifyWithBlock(block: dispatch_block_t)
  {
    if currentState != DeferredState.Determined.rawValue
    {
      let waiter = UnsafeMutablePointer<Waiter>.alloc(1)
      waiter.initialize(Waiter(block))

      // waiter will be deallocated later
      if enqueue(waiter)
      {
        return
      }
    }

    dispatch_async(queue, block)
  }

  /// Enqueue a closure to be performed asynchronously after this `Deferred` becomes determined
  ///
  /// - parameter task:  the closure to be enqueued

  public func notify(qos qos: qos_class_t = QOS_CLASS_UNSPECIFIED, task: (Result<T>) -> Void)
  {
    notifyWithBlock(createNotificationBlock(qos, task: task))
  }

  /// Query the current state of this `Deferred`
  ///
  /// - returns: a `DeferredState` (`.Waiting`, `.Executing` or `.Determined`)

  public var state: DeferredState { return DeferredState(rawValue: currentState) ?? .Executing }

  /// Query whether this `Deferred` has been determined.
  ///
  /// - returns: wheither this `Deferred` has been determined.

  public var isDetermined: Bool { return currentState == DeferredState.Determined.rawValue }

  /// Attempt to cancel the current operation, and report on whether cancellation happened successfully.
  /// A successful cancellation will determine result in a `Deferred` equivalent as if it had been initialized as follows:
  /// ```
  /// Deferred<T>(error: DeferredError.Canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation.
  /// - returns: whether the cancellation was performed successfully.

  public func cancel(reason: String = "") -> Bool
  {
    if let _ = try? determine(Result.Error(DeferredError.Canceled(reason)))
    {
      return true
    }
    /* Could not cancel, probably because this `Deferred` was already determined. */
    return false
  }

  /// Get this `Deferred` value if it has been determined, `nil` otherwise.
  /// (This call does not block)
  ///
  /// - returns: this `Deferred`'s value, or `nil`

  public func peek() -> Result<T>?
  {
    if currentState != DeferredState.Determined.rawValue
    {
      return nil
    }
    return r
  }

  /// Get this `Deferred`'s value as a `Result`, blocking if necessary until it becomes determined.
  ///
  /// - returns: this `Deferred`'s determined result

  public var result: Result<T> {
    if currentState != DeferredState.Determined.rawValue
    {
      let block = createBlock {}
      notifyWithBlock(block)
      dispatch_block_wait(block, DISPATCH_TIME_FOREVER)
    }

    return r
  }

  /// Get this `Deferred` value, blocking if necessary until it becomes determined.
  /// If the `Deferred` is determined by a `Result` in the `.Error` state, return nil.
  /// In either case, this property will block until `Deferred` is determined.
  ///
  /// - returns: this `Deferred`'s determined value, or `nil`

  public var value: T? {
    return result.value
  }

  /// Get this `Deferred` value, blocking if necessary until it becomes determined.
  /// If the `Deferred` is determined by a `Result` in the `.Error` state, return nil.
  /// In either case, this property will block until `Deferred` is determined.
  ///
  /// - returns: this `Deferred`'s determined value, or `nil`

  public var error: ErrorType? {
    return result.error
  }

  /// Get the quality-of-service class of this `Deferred`'s queue
  /// - returns: the quality-of-service class of this `Deferred`'s queue

  public var qos: qos_class_t { return dispatch_queue_get_qos_class(self.queue, nil) }

  /// Set the queue to be used for future notifications
  /// - parameter queue: the queue to be used by the returned `Deferred`
  /// - returns: a new `Deferred` whose notifications will run on `queue`

  @warn_unused_result
  public func on(queue: dispatch_queue_t) -> Deferred
  {
    if currentState == DeferredState.Determined.rawValue
    {
      return Deferred(queue: queue, result: self.r)
    }
    return Mapped(queue: queue, source: self)
  }

  /// Set the quality-of-service to use for future notifications.
  /// The returned `Deferred` will issue notifications on a concurrent queue at the specified quality-of-service class.
  /// - parameter qos: the quality-of-service class to be used by the returned `Deferred`
  /// - returns: a new `Deferred` whose notifications will run at quality-of-service `qos`

  @warn_unused_result
  public func at(qos: qos_class_t, serially: Bool = false) -> Deferred
  {
    if serially
    {
      let attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, qos, 0)
      return on(dispatch_queue_create("deferred-serial", attr))
    }

    return on(dispatch_get_global_queue(qos, 0))
  }
}


/// A mapped `Deferred`

internal final class Mapped<T>: Deferred<T>
{
  init(queue: dispatch_queue_t, source: Deferred<T>)
  {
    super.init(queue)
    source.notify { _ = try? self.determine($0) }
  }

  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `map`
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init<U>(qos: qos_class_t = QOS_CLASS_UNSPECIFIED, source: Deferred<U>, transform: (U) throws -> T)
  {
    super.init(source.queue)

    source.notify(qos: qos) {
      result in
      if self.isDetermined { return }
      self.beginExecution()
      let transformed = result.map(transform)
      _ = try? self.determine(transformed) // an error here means this `Deferred` has been canceled.
    }
  }

  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by the version of `map` that uses a transform to a `Result`.
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init<U>(qos: qos_class_t = QOS_CLASS_UNSPECIFIED, source: Deferred<U>, transform: (U) -> Result<T>)
  {
    super.init(source.queue)

    source.notify(qos: qos) {
      result in
      if self.isDetermined { return }
      self.beginExecution()
      let transformed = result.flatMap(transform)
      _ = try? self.determine(transformed) // an error here means this `Deferred` has been canceled.
    }
  }
}

internal final class Bind<T>: Deferred<T>
{
  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `flatMap`
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init<U>(qos: qos_class_t = QOS_CLASS_UNSPECIFIED, source: Deferred<U>, transform: (U) -> Deferred<T>)
  {
    super.init(source.queue)

    source.notify(qos: qos) {
      result in
      if self.isDetermined { return }
      self.beginExecution()
      switch result
      {
      case .Value(let value):
        transform(value).notify(qos: qos) {
          transformed in
          _ = try? self.determine(transformed) // an error here means this `Deferred` has been canceled.
        }

      case .Error(let error):
        _ = try? self.determine(Result.Error(error)) // an error here means this `Deferred` has been canceled.
      }
    }
  }

  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `recover` -- flatMap for the `ErrorType` path.
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init(qos: qos_class_t = QOS_CLASS_UNSPECIFIED, source: Deferred<T>, transform: (ErrorType) -> Deferred<T>)
  {
    super.init(source.queue)

    source.notify(qos: qos) {
      result in
      if self.isDetermined { return }
      self.beginExecution()
      switch result
      {
      case .Value:
        _ = try? self.determine(result)

      case .Error(let error):
        transform(error).notify(qos: qos) {
          transformed in
          _ = try? self.determine(transformed)
        }
      }
    }
  }
}

/// A `Deferred` that applies a `Deferred` transform onto its input

internal final class Applicator<T>: Deferred<T>
{
  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `apply`
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  init<U>(qos: qos_class_t = QOS_CLASS_UNSPECIFIED, source: Deferred<U>, transform: Deferred<(U) throws -> T>)
  {
    super.init(source.queue)

    source.notify(qos: qos) {
      result in
      if self.isDetermined { return }
      switch result
      {
      case .Value:
        transform.on(self.queue).notify(qos: qos) {
          transform in
          if self.isDetermined { return }
          self.beginExecution()
          let transformed = result.apply(transform)
          _ = try? self.determine(transformed) // an error here means this `Deferred` has been canceled.
        }

      case .Error(let error):
        self.beginExecution()
        _ = try? self.determine(Result.Error(error)) // an error here means this `Deferred` has been canceled.
      }
    }
  }
}

/// A `Deferred` with a time-delay

internal final class Delayed<T>: Deferred<T>
{
  /// Initialize with a `Deferred` source and a time after which this `Deferred` may become determined.
  /// The determination could be delayed further if `source` has not become determined yet,
  /// but it will not happen earlier than the time referred to by `until`.
  /// This constructor is used by `delay`
  ///
  /// - parameter queue:  the `dispatch_queue_t` onto which the created blocks should be enqueued
  /// - parameter qos:    the QOS class at which to execute the delay; defaults to the queue's QOS class.
  /// - parameter source: the `Deferred` whose value should be delayed
  /// - parameter until:  the target time until which the determination of this `Deferred` will be delayed

  init(qos: qos_class_t = QOS_CLASS_UNSPECIFIED, source: Deferred<T>, until: dispatch_time_t)
  {
    super.init(source.queue)

    source.notify(qos: qos) {
      result in
      if self.isDetermined { return }

      self.beginExecution()
      let now = dispatch_time(DISPATCH_TIME_NOW, 0)
      if until > now, case .Value = result
      {
        dispatch_after(until, self.queue, self.createBlock(qos, block: { _ = try? self.determine(result) }))
      }
      else
      {
        _ = try? self.determine(result) // an error here means this `Deferred` has been canceled.
      }
    }
  }
}

/// A `Deferred` to be determined (`TBD`) manually.

public class TBD<T>: Deferred<T>
{
  /// Initialize an undetermined `Deferred`, `TBD`.

  public override init(_ queue: dispatch_queue_t = dispatch_get_global_queue(qos_class_self(), 0))
  {
    super.init(queue)
  }

  /// Set the value of this `Deferred` and change its state to `DeferredState.Determined`
  /// Note that a `Deferred` can only be determined once. On subsequent calls, `determine` will throw an `AlreadyDetermined` error.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - throws: `DeferredError.AlreadyDetermined` if the `Deferred` was already determined upon calling this method.

  public func determine(value: T) throws
  {
    try determine(Result.Value(value))
  }

  /// Set this `Deferred` to an error and change its state to `DeferredState.Determined`
  /// Note that a `Deferred` can only be determined once. On subsequent calls, `determine` will throw an `AlreadyDetermined` error.
  ///
  /// - parameter error: the intended error for this `Deferred`
  /// - throws: `DeferredError.AlreadyDetermined` if the `Deferred` was already determined upon calling this method.

  public func determine(error: ErrorType) throws
  {
    try determine(Result.Error(error))
  }

  /// Set the `Result` of this `Deferred` and change its state to `DeferredState.Determined`
  /// Note that a `Deferred` can only be determined once. On subsequent calls, `determine` will throw an `AlreadyDetermined` error.
  ///
  /// - parameter result: the intended `Result` for this `Deferred`
  /// - throws: `DeferredError.AlreadyDetermined` if the `Deferred` was already determined upon calling this method.

  public override func determine(result: Result<T>) throws
  {
    try super.determine(result)
  }

  /// Change the state of this `TBD` from `.Waiting` to `.Executing`

  public override func beginExecution()
  {
    super.beginExecution()
  }
}
