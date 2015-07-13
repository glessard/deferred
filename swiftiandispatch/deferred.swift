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

  private var currentState: Int32 = DeferredState.Ready.rawValue
  private var waiters = UnsafeMutablePointer<Waiter>(nil)

  // MARK: Initializers

  private init() {}

  public init(value: T)
  {
    v = value
    currentState = DeferredState.Completed.rawValue
  }

  public init(queue: dispatch_queue_t, task: () -> T)
  {
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

  deinit
  {
    func stackDealloc(waiter: UnsafeMutablePointer<Waiter>)
    {
      if waiter != nil
      {
        stackDealloc(waiter)
        waiter.destroy(1)
        waiter.dealloc(1)
      }
    }
    stackDealloc(waiters)
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
        while true
        {
          let stack = waiters
          if CAS(stack, nil, &waiters)
          {
            func stackNotify(waiter: UnsafeMutablePointer<Waiter>)
            {
              if waiter != nil
              {
                stackNotify(waiter.memory.next)
                waiter.memory.wake()
                waiter.destroy(1)
                waiter.dealloc(1)
              }
            }
            stackNotify(stack)
            return true
          }
        }
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
    if currentState != DeferredState.Completed.rawValue
    {
      let thread = mach_thread_self()
      let waiter = UnsafeMutablePointer<Waiter>.alloc(1)
      waiter.initialize(Waiter(.Thread(thread)))
      while true
      {
        let head = waiters
        waiter.memory.next = head
        if currentState != DeferredState.Completed.rawValue
        {
          if CAS(head, waiter, &waiters)
          {
            let kr = thread_suspend(thread)
            guard kr == KERN_SUCCESS else { fatalError("Thread suspension failed with code \(kr)") }
            break
          }
        }
        else
        { // Deferred has a value now
          waiter.destroy(1)
          waiter.dealloc(1)
          break
        }
      }
    }
    return v
  }

  public func notify(queue: dispatch_queue_t, task: (T) -> Void)
  {
    if currentState != DeferredState.Completed.rawValue
    {
      let waiter = UnsafeMutablePointer<Waiter>.alloc(1)
      waiter.initialize(Waiter(.Dispatch(queue, { task(self.v) })))
      while true
      {
        let head = waiters
        waiter.memory.next = head
        if currentState != DeferredState.Completed.rawValue
        {
          if CAS(head, waiter, &waiters)
          {
            return
          }
        }
        else
        { // Deferred has a value now
          waiter.destroy(1)
          waiter.dealloc(1)
          break
        }
      }
    }
    dispatch_async(queue) { task(self.v) }
  }
}

public func delay(ns: Int) -> Deferred<Void>
{
  return Deferred(value: ()).delay(ns)
}

public func delay(µs µs: Int) -> Deferred<Void>
{
  return Deferred(value: ()).delay(µs: µs)
}

public func delay(ms ms: Int) -> Deferred<Void>
{
  return Deferred(value: ()).delay(ms: ms)
}

public func delay(seconds s: Double) -> Deferred<Void>
{
  return Deferred(value: ()).delay(seconds: s)
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

  public func delay(µs µs: Int) -> Deferred
  {
    return delay(µs*1000)
  }

  public func delay(ms ms: Int) -> Deferred
  {
    return delay(ms*1_000_000)
  }

  public func delay(seconds s: Double) -> Deferred
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
}

// MARK: Map: chain asynchronous tasks with input parameters and return values

extension Deferred
{
  public func map<U>(transform: (T) -> U) -> Deferred<U>
  {
    return map(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  public func map<U>(qos: qos_class_t, transform: (T) -> U) -> Deferred<U>
  {
    return map(dispatch_get_global_queue(qos, 0), transform: transform)
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
}

// MARK: Bind: chain asynchronous tasks with input parameters and return values

extension Deferred
{
  public func bind<U>(transform: (T) -> Deferred<U>) -> Deferred<U>
  {
    return bind(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  public func bind<U>(qos: qos_class_t, transform: (T) -> Deferred<U>) -> Deferred<U>
  {
    return bind(dispatch_get_global_queue(qos, 0), transform: transform)
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
  let combined = deferreds.reduce(Deferred<[T]>(value: [])) {
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


// MARK: Asynchronous tasks with return values.

public func async<T>(task: () -> T) -> Deferred<T>
{
  return Deferred(task)
}

public func async<T>(group group: dispatch_group_t, task: () -> T) -> Deferred<T>
{
  dispatch_group_enter(group)
  return Deferred {
    defer { dispatch_group_leave(group) }
    return task()
  }
}

public func async<T>(qos: qos_class_t, task: () -> T) -> Deferred<T>
{
  return Deferred(qos: qos, task: task)
}

public func async<T>(qos: qos_class_t, group: dispatch_group_t, task: () -> T) -> Deferred<T>
{
  dispatch_group_enter(group)
  return Deferred(qos: qos) {
    defer { dispatch_group_leave(group) }
    return task()
  }
}

public func async<T>(queue: dispatch_queue_t, task: () -> T) -> Deferred<T>
{
  return Deferred(queue: queue, task: task)
}

public func async<T>(queue: dispatch_queue_t, group: dispatch_group_t, task: () -> T) -> Deferred<T>
{
  dispatch_group_enter(group)
  return Deferred(queue: queue) {
    defer { dispatch_group_leave(group) }
    return task()
  }
}
