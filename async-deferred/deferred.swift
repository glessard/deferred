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

/// These errors can be thrown by a `Deferred`.
///
/// Must be a top-level type because Deferred is generic.

public enum DeferredError: ErrorType
{
  case Canceled(String)
  case AlreadyDetermined(String)
  case CannotDetermine(String)
}

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
  private var waiters: UnsafeMutablePointer<Waiter> = nil

  // MARK: initializers

  private init()
  {
    r = Result()
    currentState = DeferredState.Waiting.rawValue
  }

  deinit
  {
    WaitQueue.dealloc(waiters)
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
  /// - parameter qos:  the Quality-of-Service class at which the computation task should be performed
  /// - parameter task: the computation to be performed

  public convenience init(qos: qos_class_t, task: () throws -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  /// Initialize with a computation task to be performed in the background
  ///
  /// - parameter queue: the `dispatch_queue_t` onto which the computation task should be enqueued
  /// - parameter task:  the computation to be performed

  public convenience init(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, task: () throws -> T)
  {
    self.init()

    let block = createBlock(qos) {
      let result = Result { try task() }
      _ = try? self.determine(result) // an error here means this `Deferred` has been canceled.
    }

    currentState = DeferredState.Executing.rawValue
    dispatch_async(queue, block)
  }

  // MARK: initialize with a result, value or error

  /// Initialize to an already determined state
  ///
  /// - parameter result: the result of this `Deferred`

  public init(_ result: Result<T>)
  {
    r = result
    currentState = DeferredState.Determined.rawValue
  }

  /// Initialize to an already determined state
  ///
  /// - parameter value: the value of this `Deferred`'s `Result`

  convenience public init(value: T)
  {
    self.init(Result.Value(value))
  }

  /// Initialize to an already determined state
  ///
  /// - parameter error: the error state of this `Deferred`'s `Result`

  convenience public init(error: ErrorType)
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
        throw DeferredError.AlreadyDetermined("Attempted to determine Deferred twice with \(__FUNCTION__)")
      }
    }

    r = result

    guard OSAtomicCompareAndSwap32Barrier(transientState, DeferredState.Determined.rawValue, &currentState) else
    { // Getting here seems impossible, but try to handle it gracefully.
      throw DeferredError.CannotDetermine("Failed to determine Deferred")
    }

    while true
    {
      let queue = waiters
      if CAS(queue, nil, &waiters)
      {
        WaitQueue.notifyAll(queue)
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
        { // waiter is now enqueued
          return true
        }
      }
      else
      { // This Deferred has become determined; bail
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
    if qos == QOS_CLASS_UNSPECIFIED
    {
      return dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, block)
    }

    return dispatch_block_create_with_qos_class(DISPATCH_BLOCK_ENFORCE_QOS_CLASS, qos, 0, block)
  }

  // MARK: public interface

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
      let thread = mach_thread_self()
      let waiter = UnsafeMutablePointer<Waiter>.alloc(1)
      waiter.initialize(Waiter(.Thread(thread)))

      if enqueue(waiter)
      { // waiter will be deallocated after the thread is woken
        let kr = thread_suspend(thread)
        guard kr == KERN_SUCCESS else { fatalError("Thread suspension failed with code \(kr)") }
      }
      else
      { // Deferred has a value now
        waiter.destroy()
        waiter.dealloc(1)
      }
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

  /// Enqueue a closure to be performed asynchronously after this `Deferred` becomes determined
  ///
  /// - parameter queue: the `dispatch_queue_t` upon which the computation should be enqueued
  /// - parameter task:  the closure to be enqueued

  public func notify(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, task: (Result<T>) -> Void)
  {
    notify(queue, block: createNotificationBlock(qos, task: task))
  }

  /// Enqueue a computation to be performed upon the determination of this `Deferred`
  ///
  /// - parameter queue: the `dispatch_queue_t` upon which the computation should be enqueued
  /// - parameter block: the computation to be enqueued, as a `dispatch_block_t` or a `() -> Void` closure.

  public func notify(queue: dispatch_queue_t, block: dispatch_block_t)
  {
    if currentState != DeferredState.Determined.rawValue
    {
      let waiter = UnsafeMutablePointer<Waiter>.alloc(1)
      waiter.initialize(Waiter(.Closure(queue, block)))

      if enqueue(waiter)
      { // waiter will be deallocated after the block is dispatched to GCD
        return
      }
      else
      { // Deferred has a value now
        waiter.destroy()
        waiter.dealloc(1)
      }
    }

    dispatch_async(queue, block)
  }
}

/// A mapped `Deferred`

internal final class Mapped<T>: Deferred<T>
{
  private override init() { super.init() }

  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `map`
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  convenience init<U>(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, source: Deferred<U>, transform: (U) throws -> T)
  {
    self.init()

    source.notify(queue, qos: qos) {
      result in
      if self.isDetermined { return }
      self.beginExecution()
      let transformed = result.map(transform)
      _ = try? self.determine(transformed) // an error here means this `Deferred` has been canceled.
    }
  }

  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by the `flatMap` that uses a transform to a `Result`.
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  convenience init<U>(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, source: Deferred<U>, transform: (U) -> Result<T>)
  {
    self.init()

    source.notify(queue, qos: qos) {
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
  private override init() { super.init() }

  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `flatMap`
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  convenience init<U>(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, source: Deferred<U>, transform: (U) -> Deferred<T>)
  {
    self.init()

    source.notify(queue, qos: qos) {
      result in
      if self.isDetermined { return }
      self.beginExecution()
      switch result
      {
      case .Value(let value):
        transform(value).notify(queue, qos: qos) {
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

  convenience init(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, source: Deferred<T>, transform: (ErrorType) -> Deferred<T>)
  {
    self.init()

    source.notify(queue, qos: qos) {
      result in
      if self.isDetermined { return }
      self.beginExecution()
      switch result
      {
      case .Value:
        _ = try? self.determine(result)

      case .Error(let error):
        transform(error).notify(queue, qos: qos) {
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
  private override init() { super.init() }

  /// Initialize with a `Deferred` source and a transform to be computed in the background
  /// This constructor is used by `apply`
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be enqueued
  /// - parameter qos:       the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  convenience init<U>(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, source: Deferred<U>, transform: Deferred<(U) throws -> T>)
  {
    self.init()

    source.notify(queue, qos: qos) {
      result in
      if self.isDetermined { return }
      switch result
      {
      case .Value:
        transform.notify(queue, qos: qos) {
          transform in
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
  private override init() { super.init() }

  /// Initialize with a `Deferred` source and a time after which this `Deferred` may become determined.
  /// The determination could be delayed further if `source` has not become determined yet,
  /// but it will not happen earlier than the time referred to by `until`.
  /// This constructor is used by `delay`
  ///
  /// - parameter queue:  the `dispatch_queue_t` onto which the created blocks should be enqueued
  /// - parameter qos:    the QOS class at which to execute the delay; defaults to the queue's QOS class.
  /// - parameter source: the `Deferred` whose value should be delayed
  /// - parameter until:  the target time until which the determination of this `Deferred` will be delayed

  convenience init(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, source: Deferred<T>, until: dispatch_time_t)
  {
    self.init()

    source.notify(queue, qos: qos) {
      result in
      if self.isDetermined { return }

      self.beginExecution()
      let now = dispatch_time(DISPATCH_TIME_NOW, 0)
      if until > now, case .Value = result
      {
        dispatch_after(until, queue, self.createBlock(qos, block: { _ = try? self.determine(result) }))
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

  override public init() { super.init() }

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
