//
//  deferred.swift
//  swiftiandispatch
//
//  Created by Guillaume Lessard on 2015-07-09.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

private enum State: Int32 { case Ready = 0, Running = 1, /* Canceled = 2, */ Completed = 3, Assigning = 99 }

/**
  An asynchronous computation result.

  The `value` property will return the result, blocking until it is ready.
  If the result is ready when `value` is called, it will return immediately.
*/

public class Deferred<T>
{
  private var v: T! = nil
  private let group = dispatch_group_create()

  private var currentState: Int32 = State.Ready.rawValue

  private func setState(newState: State) -> Bool
  {
    switch newState
    {
    case .Ready:
      return currentState == State.Ready.rawValue

    case .Running:
      return OSAtomicCompareAndSwap32Barrier(State.Ready.rawValue, State.Running.rawValue, &currentState)

//    case .Canceled:
//      let s = currentState
//      if s == State.Completed.rawValue { return false }
//      return OSAtomicCompareAndSwap32Barrier(s, State.Canceled.rawValue, &currentState)

    case .Assigning:
      return OSAtomicCompareAndSwap32Barrier(State.Running.rawValue, State.Assigning.rawValue, &currentState)

    case .Completed:
      if OSAtomicCompareAndSwap32Barrier(State.Assigning.rawValue, State.Completed.rawValue, &currentState)
      {
        dispatch_group_leave(group)
        return true
      }
      return false
    }
  }

  private init()
  {
    dispatch_group_enter(group)
  }

  public init(result: T)
  {
    v = result
    currentState = State.Completed.rawValue
  }

  public convenience init(queue: dispatch_queue_t, task: () -> T)
  {
    self.init()

    guard setState(.Running) else { fatalError("Could not start task in \(__FUNCTION__)") }
    dispatch_async(queue) {
      self.setValue(task())
    }
  }

  public convenience init(queue: dispatch_queue_t, group: dispatch_group_t, task: () -> T)
  {
    dispatch_group_enter(group)
    self.init(queue: queue) {
      let result = task()
      dispatch_group_leave(group)
      return result
    }
  }

  private func setValue(result: T)
  {
    guard setState(.Assigning) else { fatalError("Could not begin assignment of result in \(__FUNCTION__)") }

    v = result

    guard setState(.Completed) else { fatalError("Could not complete assignment of result in \(__FUNCTION__)") }
  }

  public var value: T {
    if currentState != State.Completed.rawValue
    {
      dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
    }
    return v
  }
}



// MARK: Asynchronous tasks with input parameters and no return values.

extension Deferred
{
  public func notify(task: (T) -> ())
  {
    return notify(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func notify(group group: dispatch_group_t, task: (T) -> ())
  {
    return notify(dispatch_get_global_queue(qos_class_self(), 0), group: group, task: task)
  }

  public func notify(qos: qos_class_t, task: (T) -> ())
  {
    return notify(dispatch_get_global_queue(qos, 0), task: task)
  }

  public func notify(qos: qos_class_t, group: dispatch_group_t, task: (T) -> ())
  {
    return notify(dispatch_get_global_queue(qos, 0), group: group, task: task)
  }

  public func notify(queue: dispatch_queue_t, task: (T) -> ())
  {
    dispatch_group_notify(self.group, queue) {
      task(self.value)
    }
  }

  public func notify(queue: dispatch_queue_t, group: dispatch_group_t, task: (T) -> ())
  {
    dispatch_group_enter(group)
    dispatch_group_notify(self.group, queue) {
      task(self.value)
      dispatch_group_leave(group)
    }
  }
}

// MARK: Asynchronous tasks with input parameters and return values

extension Deferred
{
  public func notify<U>(task: (T) -> U) -> Deferred<U>
  {
    return notify(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func notify<U>(group group: dispatch_group_t, task: (T) -> U) -> Deferred<U>
  {
    return notify(dispatch_get_global_queue(qos_class_self(), 0), group: group, task: task)
  }

  public func notify<U>(qos: qos_class_t, task: (T) -> U) -> Deferred<U>
  {
    return notify(dispatch_get_global_queue(qos, 0), task: task)
  }

  public func notify<U>(qos: qos_class_t, group: dispatch_group_t, task: (T) -> U) -> Deferred<U>
  {
    return notify(dispatch_get_global_queue(qos, 0), group: group, task: task)
  }

  public func notify<U>(queue: dispatch_queue_t, task: (T) -> U) -> Deferred<U>
  {
    return Deferred<U>(queue: queue) { task(self.value) }
  }

  public func notify<U>(queue: dispatch_queue_t, group: dispatch_group_t, task: (T) -> U) -> Deferred<U>
  {
    dispatch_group_enter(group)

    return Deferred<U>(queue: queue, group: group) {
      let result = task(self.value)
      dispatch_group_leave(group)
      return result
    }
  }
}
