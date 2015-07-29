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
  case AlreadyDetermined(String)
  case CannotDetermine(String)
}

/**
  An asynchronous computation.

  A `Deferred` starts out undetermined, in the `.Waiting` state.
  It may then enter the `.Executing` state, and will eventually become `.Determined`.
  Once it is `.Determined`, it is ready to supply a result.

  The `value` property will return the result, blocking until it becomes determined.
  If the result is ready when `value` is called, it will return immediately.

  A closure supplied to the `notify` method will be called after the `Deferred` has become determined.
*/

public class Deferred<T>
{
  private var v: T! = nil
  private let group = dispatch_group_create()

  private var currentState: Int32 = DeferredState.Waiting.rawValue

  // MARK: Initializers

  private init()
  {
    dispatch_group_enter(group)
  }

  /// Initialize to an already determined state
  ///
  /// - parameter value: the value of this `Deferred`

  public init(value: T)
  {
    v = value
    currentState = DeferredState.Determined.rawValue
  }

  /// Initialize with a computation task to be performed in the background
  ///
  /// - parameter queue: the `dispatch_queue_t` onto which the computation task should be queued
  /// - parameter task:  the computation to be performed

  public convenience init(queue: dispatch_queue_t, task: () -> T)
  {
    self.init()

    currentState = DeferredState.Executing.rawValue
    dispatch_async(queue) {
      try! self.setValue(task())
    }
  }

  /// Initialize with a computation task to be performed in the background
  ///
  /// - parameter qos:  the Quality-of-Service class at which the computation task should be performed
  /// - parameter task: the computation to be performed

  public convenience init(qos: qos_class_t, task: () -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  /// Initialize with a computation task to be performed in the background, at the current quality of service
  ///
  /// - parameter task: the computation to be performed

  public convenience init(_ task: () -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  /// Initialize with a `Deferred` source and a transform to computed in the background
  /// This constructor is used by `map`
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be queued
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  public convenience init<U>(queue: dispatch_queue_t, source: Deferred<U>, transform: (U) -> T)
  {
    self.init()

    source.notify(queue) {
      value in
      self.beginExecution()
      try! self.setValue(transform(value))
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
      value in
      self.beginExecution()
      transform(value).notify { transformedValue in try! self.setValue(transformedValue) }
    }
  }

  /// Initialize with a `Deferred` source and a transform to computed in the background
  /// This constructor is used by `apply`
  ///
  /// - parameter queue:     the `dispatch_queue_t` onto which the computation should be queued
  /// - parameter source:    the `Deferred` whose value should be used as the input for the transform
  /// - parameter transform: the transform to be applied to `source.value` and whose result is represented by this `Deferred`

  public convenience init<U>(queue: dispatch_queue_t, source: Deferred<U>, transform: Deferred<(U) -> T>)
  {
    self.init()

    source.notify(queue) {
      value in
      transform.notify(queue) {
        transform in
        self.beginExecution()
        try! self.setValue(transform(value))
      }
    }
  }

  /// Initialize with a `Deferred` source and a delay time to be applied
  /// This constructor is used by `delay`
  ///
  /// - parameter queue:  the `dispatch_queue_t` onto which the created blocks should be queued
  /// - parameter source: the `Deferred` whose value should be delayed
  /// - parameter delay:  the amount of time by which to delay the determination of this `Deferred`

  public convenience init(queue: dispatch_queue_t, source: Deferred, delay: dispatch_time_t)
  {
    self.init()

    source.notify(queue) {
      value in
      self.beginExecution()
      dispatch_after(delay, queue) {
        try! self.setValue(value)
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
  /// - parameter value: the intended value for this `Deferred`
  /// - throws: `DeferredError.AlreadyDetermined` if the `Deferred` was already determined upon calling this method.

  private func setValue(value: T) throws
  {
    // A turnstile to ensure only one thread can succeed
    while true
    { // Allow multiple tries in case another thread concurrently switches state from .Waiting to .Executing
      let initialState = currentState
      if initialState < DeferredState.Determined.rawValue
      {
        guard OSAtomicCompareAndSwap32Barrier(initialState, transientState, &currentState) else { continue }
        break
      }
      else
      {
        assert(currentState >= DeferredState.Determined.rawValue)
        throw DeferredError.AlreadyDetermined("Attempted to determine Deferred twice with \(__FUNCTION__)")
      }
    }

    v = value

    guard OSAtomicCompareAndSwap32Barrier(transientState, DeferredState.Determined.rawValue, &currentState) else
    { // Getting here seems impossible, but try to handle it gracefully.
      throw DeferredError.CannotDetermine("Failed to determine Deferred")
    }

    dispatch_group_leave(group)
    // The result is now available for the world
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

  /// Get this `Deferred` value if it has been determined, `nil` otherwise.
  /// (This call does not block)
  ///
  /// - returns: this `Deferred`'s value, or `nil`

  public func peek() -> T?
  {
    if currentState != DeferredState.Determined.rawValue
    {
      return nil
    }
    return v
  }

  /// Get this `Deferred` value, blocking if necessary until it becomes determined.
  ///
  /// - returns: this `Deferred`'s value

  public var value: T {
    if currentState != DeferredState.Determined.rawValue { dispatch_group_wait(group, DISPATCH_TIME_FOREVER) }
    return v
  }

  /// Enqueue a computation to be performed upon the determination of this `Deferred`
  ///
  /// - parameter queue: the `dispatch_queue_t` upon which the computation should be enqueued
  /// - parameter task:  the computation to be enqueued

  public func notify(queue: dispatch_queue_t, task: (T) -> Void)
  {
    dispatch_group_notify(self.group, queue) { task(self.v) }
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
  /// None that a `Deferred` can only be determined once. On subsequent calls, `determine` will throw an `AlreadyDetermined` error.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - throws: `DeferredError.AlreadyDetermined` if the `Deferred` was already determined upon calling this method.

  public func determine(value: T) throws
  {
    try super.setValue(value)
  }

  /// Change the state of this `TBD` from `.Waiting` to `.Executing`

  public override func beginExecution()
  {
    super.beginExecution()
  }
}
