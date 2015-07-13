//
//  deferred.swift
//  swiftiandispatch
//
//  Created by Guillaume Lessard on 2015-07-09.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

public enum DeferredState: Int32 { case Ready = 0, Running = 1, /* Canceled = 2, */ Completed = 3, Assigning = 99 }

/**
  An asynchronous computation result.

  The `value` property will return the result, blocking until it is ready.
  If the result is ready when `value` is called, it will return immediately.
*/

public class Deferred<T>
{
  private var v: T! = nil
  private let group = dispatch_group_create()

  private var currentState: Int32 = DeferredState.Ready.rawValue

  // MARK: Initializers

  private init()
  {
    dispatch_group_enter(group)
  }

  public init(value: T)
  {
    v = value
    currentState = DeferredState.Completed.rawValue
  }

  public convenience init(queue: dispatch_queue_t, task: () -> T)
  {
    self.init()

    guard setState(.Running) else { fatalError("Could not start task in \(__FUNCTION__)") }
    dispatch_async(queue) {
      self.setValue(task())
    }
  }

  public convenience init(qos: qos_class_t, task: () -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  public convenience init(_ task: () -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  // MARK: private methods

  private func setState(newState: DeferredState) -> Bool
  {
    switch newState
    {
    case .Ready:
      return currentState == DeferredState.Ready.rawValue

    case .Running:
      return OSAtomicCompareAndSwap32Barrier(DeferredState.Ready.rawValue, DeferredState.Running.rawValue, &currentState)

      //    case .Canceled:
      //      let s = currentState
      //      if s == DeferredState.Completed.rawValue { return false }
      //      return OSAtomicCompareAndSwap32Barrier(s, DeferredState.Canceled.rawValue, &currentState)

    case .Assigning:
      return OSAtomicCompareAndSwap32Barrier(DeferredState.Running.rawValue, DeferredState.Assigning.rawValue, &currentState)

    case .Completed:
      if OSAtomicCompareAndSwap32Barrier(DeferredState.Assigning.rawValue, DeferredState.Completed.rawValue, &currentState)
      {
        dispatch_group_leave(group)
        return true
      }
      return currentState == DeferredState.Completed.rawValue
    }
  }
  
  private func setValue(value: T, trapOnFailure: Bool = true)
  { // A very simple turnstile to ensure only one thread can succeed
    if setState(.Assigning)
    {
      v = value
      guard setState(.Completed) else { fatalError("Could not complete assignment of value in \(__FUNCTION__)") }
      // The result is now available for the world
    }
    else if trapOnFailure { fatalError("Probable attempt to set value of Deferred twice with \(__FUNCTION__)") }
  }

  // MARK: public interface

  public var state: DeferredState { return DeferredState(rawValue: currentState)! }

  public var isComplete: Bool { return currentState == DeferredState.Completed.rawValue }

  public func peek() -> T?
  {
    if currentState != DeferredState.Completed.rawValue
    {
      return nil
    }
    return v
  }

  public var value: T {
    if currentState != DeferredState.Completed.rawValue { dispatch_group_wait(group, DISPATCH_TIME_FOREVER) }
    return v
  }

  public func notify(queue: dispatch_queue_t, task: (T) -> Void)
  {
    dispatch_group_notify(self.group, queue) { task(self.v) }
  }

  public func map<U>(queue: dispatch_queue_t, transform: (T) -> U) -> Deferred<U>
  {
    let deferred = Deferred<U>()
    self.notify(queue) {
      value in
      deferred.setState(.Running)
      deferred.setValue(transform(value))
    }
    return deferred
  }

  public func bind<U>(queue: dispatch_queue_t, transform: (T) -> Deferred<U>) -> Deferred<U>
  {
    let deferred = Deferred<U>()
    self.notify(queue) {
      value in
      deferred.setState(.Running)
      transform(value).notify(queue) { transformedValue in deferred.setValue(transformedValue) }
    }
    return deferred
  }
}

extension Deferred
{
  public func delay(ns: Int) -> Deferred
  {
    if ns < 0 { return self }

    let delayed = Deferred<T>()
    self.notify {
      value in
      delayed.setState(.Running)
      let delay = dispatch_time(DISPATCH_TIME_NOW, Int64(ns))
      dispatch_after(delay, dispatch_get_global_queue(qos_class_self(), 0)) {
        delayed.setValue(value)
      }
    }
    return delayed
  }
}

public func firstCompleted<T>(deferreds: [Deferred<T>]) -> Deferred<T>
{
  let first = Deferred<T>()
  for d in deferreds.shuffle()
  {
    d.notify {
      value in
      first.setState(.Running)
      first.setValue(value, trapOnFailure: false)
    }
  }
  return first
}
