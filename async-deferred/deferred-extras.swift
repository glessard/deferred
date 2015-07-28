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

// MARK: Create asynchronous tasks with return values.

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

// MARK: Delay: enforce a minimum time before a `Deferred` has a value

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

    let queue = dispatch_get_global_queue(qos_class_self(), 0)
    let delay = dispatch_time(DISPATCH_TIME_NOW, Int64(ns))
    return Deferred(queue: queue, source: self, delay: delay)
  }
}

// MARK: Timeout: enforce a maximum time before a `Deferred` has becomes determined

extension Deferred
{
  public func timeout(µs µs: Int) -> Deferred
  {
    return timeout(ns: µs*1000)
  }

  public func timeout(ms ms: Int) -> Deferred
  {
    return timeout(ns: ms*1_000_000)
  }

  public func timeout(seconds s: Double) -> Deferred
  {
    return timeout(ns: Int(s*1e9))
  }

  public func timeout(ns ns: Int) -> Deferred
  {
    if self.isDetermined || ns < 0 { return self }

    let queue = dispatch_get_global_queue(qos_class_self(), 0)
    let timeout = dispatch_time(DISPATCH_TIME_NOW, Int64(ns))

    let perishable = map(queue) { $0 }
    dispatch_after(timeout, queue) { perishable.cancel("Operation timed out") }
    return perishable
  }
}

// MARK: onValue: execute a task when (and only when) a computation succeeds

extension Deferred
{
  public func onValue(task: (T) -> Void)
  {
    onValue(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func onValue(qos: qos_class_t, task: (T) -> Void)
  {
    onValue(dispatch_get_global_queue(qos, 0), task: task)
  }

  public func onValue(queue: dispatch_queue_t, task: (T) -> Void)
  {
    notify(queue) { if let value = $0.value { task(value) } }
  }
}

// MARK: onError: execute a task when (and only when) a computation fails

extension Deferred
{
  public func onError(task: (ErrorType) -> Void)
  {
    onError(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func onError(qos: qos_class_t, task: (ErrorType) -> Void)
  {
    onError(dispatch_get_global_queue(qos, 0), task: task)
  }

  public func onError(queue: dispatch_queue_t, task: (ErrorType) -> Void)
  {
    notify(queue) { if let error = $0.error { task(error) } }
  }
}

// MARK: Notify: execute a task with the result of an asynchronous computation.

extension Deferred
{
  public func notify(task: (Result<T>) -> Void)
  {
    notify(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func notify(qos: qos_class_t, task: (Result<T>) -> Void)
  {
    notify(dispatch_get_global_queue(qos, 0), task: task)
  }
}

// MARK: Map: transform an asynchronous operand

extension Deferred
{
  public func map<U>(transform: (T) throws -> U) -> Deferred<U>
  {
    return map(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  public func map<U>(qos: qos_class_t, transform: (T) throws -> U) -> Deferred<U>
  {
    return map(dispatch_get_global_queue(qos, 0), transform: transform)
  }

  public func map<U>(queue: dispatch_queue_t, transform: (T) throws -> U) -> Deferred<U>
  {
    return Deferred<U>(queue: queue, source: self, transform: transform)
  }
}

// MARK: flatMap: transform an asynchronous operand

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
    return Deferred<U>(queue: queue, source: self, transform: transform)
  }
}

// MARK: flatMap: transform an asynchronous operand

extension Deferred
{
  public func flatMap<U>(transform: (T) -> Result<U>) -> Deferred<U>
  {
    return flatMap(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  public func flatMap<U>(qos: qos_class_t, transform: (T) -> Result<U>) -> Deferred<U>
  {
    return flatMap(dispatch_get_global_queue(qos, 0), transform: transform)
  }
  
  public func flatMap<U>(queue: dispatch_queue_t, transform: (T) -> Result<U>) -> Deferred<U>
  {
    return Deferred<U>(queue: queue, source: self, transform: transform)
  }
}

// MARK: Apply: apply an asynchronous transform to an asynchronous operand

extension Deferred
{
  public func apply<U>(transform: Deferred<(T)throws->U>) -> Deferred<U>
  {
    return apply(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  public func apply<U>(qos: qos_class_t, transform: Deferred<(T)throws->U>) -> Deferred<U>
  {
    return apply(dispatch_get_global_queue(qos, 0), transform: transform)
  }

  public func apply<U>(queue: dispatch_queue_t, transform: Deferred<(T)throws->U>) -> Deferred<U>
  {
    return Deferred<U>(queue: queue, source: self, transform: transform)
  }
}

// combine two or more Deferred objects into one.

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

public func firstDetermined<T>(deferreds: [Deferred<T>]) -> Deferred<T>
{
  let first = TBD<T>()
  for d in deferreds.shuffle()
  {
    d.notify {
      result in
      do { try first.determine(result) }
      catch { /* We don't care, it just means it's not the first completed */ }
    }
  }
  return first
}
