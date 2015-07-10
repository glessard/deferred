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
  
  private func setValue(result: T)
  { // A very simple turnstile to ensure only one thread can succeed
    guard setState(.Assigning) else { fatalError("Probable attempt at setting a Deferred value twice with \(__FUNCTION__)") }

    v = result

    guard setState(.Completed) else { fatalError("Could not complete assignment of result in \(__FUNCTION__)") }
    // The result is now available for the world
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
    if currentState != DeferredState.Completed.rawValue
    {
      dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
    }
    return v
  }
}



// MARK: Notify: chain asynchronous tasks with input parameters and no return values.

extension Deferred
{
  public func notify(task: (T) -> Void)
  {
    return notify(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func notify(qos: qos_class_t, task: (T) -> Void)
  {
    return notify(dispatch_get_global_queue(qos, 0), task: task)
  }

  public func notify(queue: dispatch_queue_t, task: (T) -> Void)
  {
    dispatch_group_notify(self.group, queue) { task(self.v) }
  }
}

// MARK: Map: chain asynchronous tasks with input parameters and return values

extension Deferred
{
  public func map<U>(task: (T) -> U) -> Deferred<U>
  {
    return map(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func map<U>(qos: qos_class_t, task: (T) -> U) -> Deferred<U>
  {
    return map(dispatch_get_global_queue(qos, 0), task: task)
  }

  public func map<U>(queue: dispatch_queue_t, task: (T) -> U) -> Deferred<U>
  {
    let deferred = Deferred<U>()
    self.notify(queue) {
      (result: T) -> Void in
      deferred.setState(.Running)
      deferred.setValue(task(result))
    }
    return deferred
  }
}

// MARK: Bind: chain asynchronous tasks with input parameters and return values

extension Deferred
{
  public func bind<U>(task: (T) -> Deferred<U>) -> Deferred<U>
  {
    return bind(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func bind<U>(qos: qos_class_t, task: (T) -> Deferred<U>) -> Deferred<U>
  {
    return bind(dispatch_get_global_queue(qos, 0), task: task)
  }

  public func bind<U>(queue: dispatch_queue_t, task: (T) -> Deferred<U>) -> Deferred<U>
  {
    let deferred = Deferred<U>()
    self.notify(queue) {
      (result: T) -> Void in
      deferred.setState(.Running)
      task(result).notify(queue) { deferred.setValue($0) }
    }
    return deferred
  }
}


extension Deferred
{
  public func combine<U>(other: Deferred<U>) -> Deferred<(T,U)>
  {
    return bind { (t: T) in other.map { (u: U) in (t,u) } }
  }

  public func combine<U,V>(o1: Deferred<U>, _ o2: Deferred<V>) -> Deferred<(T,U,V)>
  {
    return combine(o1).bind { (t: T, u: U) in o2.map { (v: V) in (t,u,v) } }
  }

  public func combine(other: [Deferred<T>]) -> Deferred<[T]>
  {
    let mappedSelf = map { (t: T) in [t] }

    if other.count == 0
    {
      return mappedSelf
    }

    let combined = other.reduce(mappedSelf) {
      (combiner: Deferred<[T]>, element: Deferred<T>) -> Deferred<[T]> in
      return element.bind {
        (t: T) in
        combiner.map {
          (var values: [T]) -> [T] in
          values.append(t)
          return values
        }
      }
    }

    return combined
  }
}
