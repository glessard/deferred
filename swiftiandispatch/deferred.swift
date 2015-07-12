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
      self.value = task()
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
  
  private func setValue(result: T, trapOnFailure: Bool = true)
  { // A very simple turnstile to ensure only one thread can succeed
    if setState(.Assigning)
    {
      v = result
      guard setState(.Completed) else { fatalError("Could not complete assignment of result in \(__FUNCTION__)") }
      // The result is now available for the world
    }
    else if trapOnFailure { fatalError("Probable attempt at setting a Deferred value twice with \(__FUNCTION__)") }
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

  public /* private(set) */ var value: T {
    get {
      if currentState != DeferredState.Completed.rawValue { dispatch_group_wait(group, DISPATCH_TIME_FOREVER) }
      return v
    }
    set {
      setValue(newValue, trapOnFailure: true)
    }
  }
}

public func delay(ns: Int) -> Deferred<Void>
{
  return Deferred(value: ()).delay(ns)
}

public func delay(µs µs: Int) -> Deferred<Void>
{
  return delay(µs*1000)
}

public func delay(ms ms: Int) -> Deferred<Void>
{
  return delay(ms*1_000_000)
}

public func delay(seconds s: NSTimeInterval) -> Deferred<Void>
{
  return delay(Int(s*1e9))
}

extension Deferred
{
  public func delay(ns: Int) -> Deferred
  {
    if ns < 0 { return self }

    let delayed = Deferred<T>()
    delayed.setState(.Running)
    let delay = dispatch_time(DISPATCH_TIME_NOW, Int64(ns>0 ? ns:0))
    dispatch_after(delay, dispatch_get_global_queue(qos_class_self(), 0)) {
      if self.currentState == DeferredState.Completed.rawValue
      {
        delayed.value = self.v
        return
      }

      dispatch_group_notify(self.group, dispatch_get_global_queue(qos_class_self(), 0)) {
        delayed.value = self.v
      }
    }

    return delayed
  }

  public func delay(µs µs: Int) -> Deferred
  {
    return delay(µs*1000)
  }

  public func delay(ms ms: Int) -> Deferred
  {
    return delay(ms*1_000_000)
  }

  public func delay(seconds s: NSTimeInterval) -> Deferred
  {
    return delay(Int(s*1e9))
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
      deferred.value = task(result)
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
      task(result).notify(queue) { deferred.value = $0 }
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

  public func combine<U1,U2>(o1: Deferred<U1>, _ o2: Deferred<U2>) -> Deferred<(T,U1,U2)>
  {
    return combine(o1).bind { (t,u1) in o2.map { u2 in (t,u1,u2) } }
  }

  public func combine<U1,U2,U3>(o1: Deferred<U1>, _ o2: Deferred<U2>, _ o3: Deferred<U3>) -> Deferred<(T,U1,U2,U3)>
  {
    return combine(o1,o2).bind { (t,u1,u2) in o3.map { u3 in (t,u1,u2,u3) } }
  }

  public func combine<C: CollectionType where C.Generator.Element == Deferred<T>>(others: C) -> Deferred<[T]>
  {
    let mappedSelf = map { (t: T) in [t] }

    if others.count == 0
    {
      return mappedSelf
    }

    let combined = others.reduce(mappedSelf) {
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

  public func combine(others: [Deferred<T>]) -> Deferred<[T]>
  {
    return combine(AnyRandomAccessCollection(others))
  }
}

public func combine<T>(deferreds: [Deferred<T>]) -> Deferred<[T]>
{
  if deferreds.count == 0
  {
    return Deferred(value: Array<T>())
  }

  let head = deferreds[0]

  if deferreds.count == 1
  {
    return head.map { t in [t] }
  }

  let tail = deferreds[1..<deferreds.count]
  return head.combine(tail)
}

public func firstCompleted<T>(deferreds: [Deferred<T>]) -> Deferred<T>
{
  let first = Deferred<T>()
  for d in deferreds.shuffle()
  {
    d.notify {
      (result: T) in
      first.setState(.Running)
      first.setValue(result, trapOnFailure: false)
    }
  }
  return first
}
