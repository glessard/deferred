//
//  deferred-extras.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

/*
  Definitions that rely on or extend Deferred, but do not need the fundamental, private stuff.
*/

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

public func delay(ns ns: Int) -> Deferred<Void>
{
  return Deferred(value: ()).delay(ns: ns)
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
  public func delay(µs µs: Int) -> Deferred
  {
    return delay(ns: µs*1000)
  }

  public func delay(ms ms: Int) -> Deferred
  {
    return delay(ns: ms*1_000_000)
  }

  public func delay(seconds s: Double) -> Deferred
  {
    return delay(ns: Int(s*1e9))
  }
  
  public func delay(ns ns: Int) -> Deferred
  {
    if ns < 0 { return self }

    let delayed = TBD<T>()
    self.notify {
      value in
      delayed.beginExecution()
      let delay = dispatch_time(DISPATCH_TIME_NOW, Int64(ns))
      dispatch_after(delay, dispatch_get_global_queue(qos_class_self(), 0)) {
        try! delayed.determine(value)
      }
    }
    return delayed
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
    let deferred = TBD<U>()
    self.notify(queue) {
      value in
      deferred.beginExecution()
      try! deferred.determine(transform(value))
    }
    return deferred
  }
}

// MARK: flatMap: chain asynchronous tasks with input parameters and return values

extension Deferred
{
  public func flatMap<U>(transform: (T) -> Deferred<U>) -> Deferred<U>
  {
    return flatMap(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  public func flatMap<U>(qos: qos_class_t, transform: (T) -> Deferred<U>) -> Deferred<U>
  {
    return flatMap(dispatch_get_global_queue(qos, 0), transform: transform)
  }

  public func flatMap<U>(queue: dispatch_queue_t, transform: (T) -> Deferred<U>) -> Deferred<U>
  {
    let deferred = TBD<U>()
    self.notify(queue) {
      value in
      deferred.beginExecution()
      transform(value).notify(queue) { transformedValue in try! deferred.determine(transformedValue) }
    }
    return deferred
  }
}

extension Deferred
{
  public func apply<U>(transform: Deferred<(T)->U>) -> Deferred<U>
  {
    return apply(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  public func apply<U>(qos: qos_class_t, transform: Deferred<(T)->U>) -> Deferred<U>
  {
    return apply(dispatch_get_global_queue(qos, 0), transform: transform)
  }

  public func apply<U>(queue: dispatch_queue_t, transform: Deferred<(T)->U>) -> Deferred<U>
  {
    let deferred = TBD<U>()
    self.notify(queue) {
      value in
      transform.notify(queue) {
        transform in
        deferred.beginExecution()
        try! deferred.determine(transform(value))
      }
    }
    return deferred
  }
}

// MARK: Combine two or more Deferred objects into one.

extension Deferred
{
  public func combine<U>(other: Deferred<U>) -> Deferred<(T,U)>
  {
    return flatMap { (t: T) in other.map { (u: U) in (t,u) } }
  }

  public func combine<U1,U2>(o1: Deferred<U1>, _ o2: Deferred<U2>) -> Deferred<(T,U1,U2)>
  {
    return combine(o1).flatMap { (t,u1) in o2.map { u2 in (t,u1,u2) } }
  }

  public func combine<U1,U2,U3>(o1: Deferred<U1>, _ o2: Deferred<U2>, _ o3: Deferred<U3>) -> Deferred<(T,U1,U2,U3)>
  {
    return combine(o1,o2).flatMap { (t,u1,u2) in o3.map { u3 in (t,u1,u2,u3) } }
  }
}

public func combine<T>(deferreds: [Deferred<T>]) -> Deferred<[T]>
{
  let combined = deferreds.reduce(Deferred<[T]>(value: [])) {
    (combiner: Deferred<[T]>, element: Deferred<T>) -> Deferred<[T]> in
    return element.flatMap {
      value in
      combiner.map {
        (var values: [T]) -> [T] in
        values.append(value)
        return values
      }
    }
  }
  return combined
}

public func firstCompleted<T>(deferreds: [Deferred<T>]) -> Deferred<T>
{
  let first = TBD<T>()
  for d in deferreds.shuffle()
  {
    d.notify {
      value in
      do {
        try first.determine(value)
      } catch { /* We don't care, it just means it's not the first completed */ }
    }
  }
  return first
}
