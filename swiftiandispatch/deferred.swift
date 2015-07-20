//
//  deferred.swift
//  swiftiandispatch
//
//  Created by Guillaume Lessard on 2015-07-09.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  The states a Deferred can be in.

  Must be a top-level type because Deferred is generic.
*/

public enum DeferredState: Int32 { case Waiting = 0, Executing = 1, Determined = 3, Assigning = -1 }

/**
  The errors a Deferred can throw.

  Must be a top-level type because Deferred is generic.
*/

public enum DeferredError: ErrorType
{
  case Canceled(String)
  case AlreadyDetermined(String)
  case CannotDetermine(String)
}

/**
  An asynchronous computation.

  A `Deferred` starts out undetermined, in the `.Waiting` state. It may then enter the `.Executing` state,
  and will eventually become `.Determined`, and ready to supply a result.

  The `result` property will return the result, blocking until it becomes determined.
  If the result is ready when `result` is called, it will return immediately.
*/

public class Deferred<T>
{
  private var r: Result<T>! = nil
  private let group = dispatch_group_create()

  // Swift does not have a facility to read and write enum values atomically.
  // To get around this, we use a raw `Int32` value as a proxy for the enum value.

  private var currentState: Int32 = DeferredState.Waiting.rawValue

  // MARK: Initializers

  private init()
  {
    dispatch_group_enter(group)
  }

  // Initialize with a background task to perform

  public convenience init(queue: dispatch_queue_t, task: () throws -> T)
  {
    self.init()

    guard setState(.Executing) else { fatalError("Could not start task in \(__FUNCTION__)") }
    dispatch_async(queue) {
      let result: Result<T>
      do {
        let v = try task()
        result = .Value(v)
      }
      catch {
        result = .Error(error)
      }
      do {
        try self.setResult(result)
      }
      catch { /* an error here means this `Deferred` was canceled before `task()` was complete. */ }
    }
  }

  public convenience init(qos: qos_class_t, task: () throws -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  public convenience init(_ task: () throws -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  // Initialize to an already Determined state.

  public init(result: Result<T>)
  {
    r = result
    currentState = DeferredState.Determined.rawValue
  }

  convenience public init(value: T)
  {
    self.init(result: Result(value: value))
  }

  convenience public init(error: ErrorType)
  {
    self.init(result: Result(error: error))
  }
  
  // MARK: private methods

  private func setState(newState: DeferredState) -> Bool
  {
    switch newState
    {
    case .Waiting:
      return currentState == DeferredState.Waiting.rawValue

    case .Executing:
      return OSAtomicCompareAndSwap32Barrier(DeferredState.Waiting.rawValue, DeferredState.Executing.rawValue, &currentState)

    case .Assigning:
      return OSAtomicCompareAndSwap32Barrier(DeferredState.Executing.rawValue, DeferredState.Assigning.rawValue, &currentState)

    case .Determined:
      if OSAtomicCompareAndSwap32Barrier(DeferredState.Assigning.rawValue, DeferredState.Determined.rawValue, &currentState)
      {
        dispatch_group_leave(group)
        return true
      }
      return currentState == DeferredState.Determined.rawValue
    }
  }
  
  private func setResult(result: Result<T>) throws
  { // A very simple turnstile to ensure only one thread can succeed
    guard setState(.Assigning) else
    {
      if currentState == DeferredState.Determined.rawValue
      {
        throw DeferredError.AlreadyDetermined("Failed attempt to determine Deferred twice with \(__FUNCTION__)")
      }
      throw DeferredError.CannotDetermine("Deferred in wrong state at start of \(__FUNCTION__)")
    }

    r = result

    guard setState(.Determined) else
    { // We cannot know where to go from here. Happily getting here seems impossible.
      fatalError("Could not complete assignment of value in \(__FUNCTION__)")
    }

    // The result is now available for the world
  }

  // MARK: public interface

  public var state: DeferredState { return DeferredState(rawValue: currentState)! }

  public var isDetermined: Bool { return currentState == DeferredState.Determined.rawValue }

  public func cancel(reason: String = "") -> Bool
  {
    setState(.Executing)
    do {
      try setResult(Result(error: DeferredError.Canceled(reason)))
      return true
    }
    catch {
      return false
    }
  }

  public func peek() -> T?
  {
    if currentState != DeferredState.Determined.rawValue
    {
      return nil
    }
    return r.value
  }

  public var result: Result<T> {
    if currentState != DeferredState.Determined.rawValue { dispatch_group_wait(group, DISPATCH_TIME_FOREVER) }
    return r
  }

  public var value: T? {
    return result.value
  }

  public var error: ErrorType? {
    return result.error
  }

  public func notify(queue: dispatch_queue_t, task: (Result<T>) -> Void)
  {
    dispatch_group_notify(self.group, queue) { task(self.r) }
  }
}

/**
  A Deferred to be determined (TBD) manually.
*/

public class TBD<T>: Deferred<T>
{
  override public init() { super.init() }

  public func determine(value: T) throws
  {
    try determine(Result(value: value))
  }

  public func determine(error: ErrorType) throws
  {
    try determine(Result(error: error))
  }

  public func determine(result: Result<T>) throws
  {
    super.setState(.Executing)
    try super.setResult(result)
  }

  public func beginExecution()
  {
    super.setState(.Executing)
  }
}
