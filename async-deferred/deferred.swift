//
//  deferred.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-09.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  The possible states of a `Deferred`.

  Must be a top-level type because Deferred is generic.
*/

public enum DeferredState: Int32 { case Waiting = 0, Executing = 1, Determined = 2 }
private let transientState = Int32.max

/**
  These errors can be thrown by a `Deferred`.

  Must be a top-level type because Deferred is generic.
*/

public enum DeferredError: ErrorType
{
  case Canceled(String)
  case AlreadyDetermined(String)
  case CannotDetermine(String)
  case Undetermined
}

/**
  An asynchronous computation.

  A `Deferred` starts out undetermined, in the `.Waiting` state.
  It may then enter the `.Executing` state, and will eventually become `.Determined`.
  Once it is `.Determined`, it is ready to supply a result.

  The `result` property will return the result, blocking until it becomes determined.
  If the result is ready when `result` is called, it will return immediately.

  A closure supplied to the `notify` method will be called after the `Deferred` has become determined.
*/

public class Deferred<T>
{
  private var r: Result<T>

  // Swift does not have a facility to read and write enum values atomically.
  // To get around this, we use a raw `Int32` value as a proxy for the enum value.

  private var currentState: Int32 = DeferredState.Waiting.rawValue
  private var waiters = UnsafeMutablePointer<Waiter>(nil)

  // MARK: Initializers

  private init()
  {
    r = Result(error: DeferredError.Undetermined)
  }

  deinit
  {
    WaitQueue.dealloc(waiters)
  }

  /// Initialize with a computation task to be performed in the background
  ///
  /// - parameter queue: the `dispatch_queue_t` onto which the computation task should be queued
  /// - parameter task:  the computation to be performed

  public convenience init(queue: dispatch_queue_t, task: () throws -> T)
  {
    self.init()

    currentState = DeferredState.Executing.rawValue
    dispatch_async(queue) {
      let result = Result<T> { try task() }
      do {  try self.setResult(result) }
      catch { /* an error here means this `Deferred` was canceled before `task()` was complete. */ }
    }
  }

  /// Initialize with a computation task to be performed in the background
  ///
  /// - parameter qos:  the Quality-of-Service class at which the computation task should be performed
  /// - parameter task: the computation to be performed

  public convenience init(qos: qos_class_t, task: () throws -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  /// Initialize with a computation task to be performed in the background, at the current quality of service
  ///
  /// - parameter task: the computation to be performed

  public convenience init(_ task: () throws -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  /// Initialize to an already determined state
  ///
  /// - parameter result: the result of this `Deferred`

  public init(result: Result<T>)
  {
    r = result
    currentState = DeferredState.Determined.rawValue
  }

  /// Initialize to an already determined state
  ///
  /// - parameter value: the value of this `Deferred`'s `Result`

  convenience public init(value: T)
  {
    self.init(result: Result(value: value))
  }

  /// Initialize to an already determined state
  ///
  /// - parameter error: the error state of this `Deferred`'s `Result`

  convenience public init(error: ErrorType)
  {
    self.init(result: Result(error: error))
  }

  /// Initialize with a `Deferred` source and a transform to computed in the background
  /// This constructor is used by `map`
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be queued
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  public convenience init<U>(queue: dispatch_queue_t, source: Deferred<U>, transform: (U) throws -> T)
  {
    self.init()

    source.notify(queue) {
      result in
      self.beginExecution()
      let transformed = result.map(transform)
      do { try self.setResult(transformed) }
      catch { /* an error here means `self` was canceled before `transform()` completed */ }
    }
  }

  /// Initialize with a `Deferred` source and a transform to computed in the background
  /// This constructor is used by `flatMap`
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be queued
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  public convenience init<U>(queue: dispatch_queue_t, source: Deferred<U>, transform: (U) -> Deferred<T>)
  {
    self.init()

    source.notify(queue) {
      result in
      self.beginExecution()
      switch result
      {
      case .Value(let value):
        transform(value).notify(queue) {
          transformed in
          do { try self.setResult(transformed) }
          catch { /* an error here means `self` was canceled before `transform()` completed */ }
        }

      case .Error(let error):
        do { try self.setResult(Result(error: error)) }
        catch { /* an error here seems irrelevant */ }
      }
    }
  }

  /// Initialize with a `Deferred` source and a transform to computed in the background
  /// This constructor is used by `flatMap`
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be queued
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  public convenience init<U>(queue: dispatch_queue_t, source: Deferred<U>, transform: (U) -> Result<T>)
  {
    self.init()

    source.notify(queue) {
      result in
      self.beginExecution()
      let transformed = result.flatMap(transform)
      do { try self.setResult(transformed) }
      catch { /* an error here means `self` was canceled before `transform()` completed */ }
    }
  }

  /// Initialize with a `Deferred` source and a transform to computed in the background
  /// This constructor is used by `apply`
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be queued
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  public convenience init<U>(queue: dispatch_queue_t, source: Deferred<U>, transform: Deferred<(U) throws -> T>)
  {
    self.init()

    source.notify(queue) {
      result in
      switch result
      {
      case .Value:
        transform.notify(queue) {
          transform in
          self.beginExecution()
          let transformed = result.apply(transform)
          do { try self.setResult(transformed) }
          catch { /* an error here means `self` was canceled before `transform()` completed */ }
        }

      case .Error(let error):
        self.beginExecution()
        do { try self.setResult(Result(error: error)) }
        catch { /* an error here seems irrelevant */ }
      }
    }
  }

  /// Initialize with a `Deferred` source and a time after which this `Deferred` may become determined.
  /// The determination could be delayed further if `source` has not become determined yet,
  /// but it will not happen earlier than the time referred to by `until`.
  /// This constructor is used by `delay`
  ///
  /// - parameter queue:  the `dispatch_queue_t` onto which the created blocks should be queued
  /// - parameter source: the `Deferred` whose value should be delayed
  /// - parameter until:  the target time until which the determination of this `Deferred` will be delayed

  public convenience init(queue: dispatch_queue_t, source: Deferred, until: dispatch_time_t)
  {
    self.init()

    source.notify(queue) {
      result in
      self.beginExecution()

      let now = dispatch_time(DISPATCH_TIME_NOW, 0)
      if until > now, case .Value = result
      {
        dispatch_after(until, queue) {
          do { try self.setResult(result) }
          catch { /* an error here seems means `self` was canceled before the delay ended */ }
        }
      }
      else
      {
        do { try self.setResult(result) }
        catch { /* an error here seems means `self` was canceled before `result` was ready */ }
      }
    }
  }

  // MARK: private methods

  /// Change the state of this `Deferred` from `.Waiting` to `.Executing`

  private func beginExecution()
  {
    OSAtomicCompareAndSwap32Barrier(DeferredState.Waiting.rawValue, DeferredState.Executing.rawValue, &currentState)
  }

  /// Set the value of this `Deferred` and change its state to `DeferredState.Determined`
  /// None that a `Deferred` can only be determined once. On subsequente calls `setValue` will throw an `AlreadyDetermined` error.
  ///
  /// - parameter result: the intended `Result` to determine this `Deferred`
  /// - throws: `DeferredError.AlreadyDetermined` if the `Deferred` was already determined upon calling this method.

  private func setResult(result: Result<T>) throws
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
  /// - returns: whether the cancellation was performed succesfully.

  public func cancel(reason: String = "") -> Bool
  {
    do {
      try setResult(Result(error: DeferredError.Canceled(reason)))
      return true
    }
    catch { /* Could not cancel, probably because this `Deferred` was already determined. */ }
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
      {
        waiter.destroy(1)
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

  public func notify(queue: dispatch_queue_t, task: (Result<T>) -> Void)
  {
    let block = { task(self.r) } // This cannot be [weak self]

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
        waiter.destroy(1)
        waiter.dealloc(1)
      }
    }

    dispatch_async(queue, block)
  }
}

/**
  A `Deferred` to be determined (`TBD`) manually.
*/

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
    try determine(Result(value: value))
  }

  /// Set this `Deferred` to an error and change its state to `DeferredState.Determined`
  /// Note that a `Deferred` can only be determined once. On subsequent calls, `determine` will throw an `AlreadyDetermined` error.
  ///
  /// - parameter error: the intended error for this `Deferred`
  /// - throws: `DeferredError.AlreadyDetermined` if the `Deferred` was already determined upon calling this method.

  public func determine(error: ErrorType) throws
  {
    try determine(Result(error: error))
  }

  /// Set the `Result` of this `Deferred` and change its state to `DeferredState.Determined`
  /// Note that a `Deferred` can only be determined once. On subsequent calls, `determine` will throw an `AlreadyDetermined` error.
  ///
  /// - parameter result: the intended `Result` for this `Deferred`
  /// - throws: `DeferredError.AlreadyDetermined` if the `Deferred` was already determined upon calling this method.

  public func determine(result: Result<T>) throws
  {
    try super.setResult(result)
  }

  /// Change the state of this `TBD` from `.Waiting` to `.Executing`

  public override func beginExecution()
  {
    super.beginExecution()
  }
}
