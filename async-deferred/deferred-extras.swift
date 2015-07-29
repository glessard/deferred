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

// MARK: asynchronous tasks with return values.

/// Utility shortcut for Grand Central Dispatch
///
/// A queue or a qos_class_t can be provided as a parameter in addition to the closure.
/// When none is supplied, the global queue at the current qos class will be used.
/// In all cases, a dispatch_group_t may be associated with the block to be executed.
///
/// - parameter task: a closure with a return value, to be executed asynchronously.
/// - returns: a `Deferred` reference, representing the return value of the closure

public func async<T>(task: () -> T) -> Deferred<T>
{
  return Deferred(task)
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter group: a `dispatch_group_t` to associate to this block execution
/// - parameter task: a closure with a return value, to be executed asynchronously.
/// - returns: a `Deferred` reference, representing the return value of the closure

public func async<T>(group group: dispatch_group_t, task: () -> T) -> Deferred<T>
{
  dispatch_group_enter(group)
  return Deferred {
    defer { dispatch_group_leave(group) }
    return task()
  }
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter qos: the quality-of-service class to associate to this block
/// - parameter task: a closure with a return value, to be executed asynchronously.
/// - returns: a `Deferred` reference, representing the return value of the closure

public func async<T>(qos: qos_class_t, task: () -> T) -> Deferred<T>
{
  return Deferred(qos: qos, task: task)
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter qos: the quality-of-service class to associate to this block
/// - parameter group: a `dispatch_group_t` to associate to this block execution
/// - parameter task: a closure with a return value, to be executed asynchronously.
/// - returns: a `Deferred` reference, representing the return value of the closure

public func async<T>(qos: qos_class_t, group: dispatch_group_t, task: () -> T) -> Deferred<T>
{
  dispatch_group_enter(group)
  return Deferred(qos: qos) {
    defer { dispatch_group_leave(group) }
    return task()
  }
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter queue: the `dispatch_queue_t` onto which the block should be added for execution
/// - parameter group: a `dispatch_group_t` to associate to this block execution
/// - parameter task: a closure with a return value, to be executed asynchronously.
/// - returns: a `Deferred` reference, representing the return value of the closure

public func async<T>(queue: dispatch_queue_t, task: () -> T) -> Deferred<T>
{
  return Deferred(queue: queue, task: task)
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter queue: the `dispatch_queue_t` onto which the block should be added for execution
/// - parameter group: a `dispatch_group_t` to associate to this block execution
/// - parameter task: a closure with a return value, to be executed asynchronously.
/// - returns: a `Deferred` reference, representing the return value of the closure

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
  /// Return a `Deferred` whose determination will occur at least `µs` microseconds from the time of evaluation.
  /// - parameter µs: a number of microseconds
  /// - returns: a `Deferred` reference

  public func delay(µs µs: Int) -> Deferred
  {
    return delay(ns: µs*1000)
  }

  /// Return a `Deferred` whose determination will occur at least `ms` milliseconds from the time of evaluation.
  /// - parameter ms: a number of milliseconds
  /// - returns: a `Deferred` reference

  public func delay(ms ms: Int) -> Deferred
  {
    return delay(ns: ms*1_000_000)
  }

  /// Return a `Deferred` whose determination will occur at least a number of seconds from the time of evaluation.
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - returns: a `Deferred` reference

  public func delay(seconds s: Double) -> Deferred
  {
    return delay(ns: Int(s*1e9))
  }
  
  /// Return a `Deferred` whose determination will occur at least `ns` nanoseconds from the time of evaluation.
  /// - parameter ns: a number of nanoseconds
  /// - returns: a `Deferred` reference

  public func delay(ns ns: Int) -> Deferred
  {
    if ns < 0 { return self }

    let queue = dispatch_get_global_queue(qos_class_self(), 0)
    let until = dispatch_time(DISPATCH_TIME_NOW, Int64(ns))
    return Deferred(queue: queue, source: self, until: until)
  }
}

// MARK: Notify: execute a task with the result of an asynchronous computation.

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

// MARK: Map: transform an asynchronous operand

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

// MARK: Apply: apply an asynchronous transform to an asynchronous operand

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
    return Deferred<U>(queue: queue, source: self, transform: transform)
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

public func firstDetermined<T>(deferreds: [Deferred<T>]) -> Deferred<T>
{
  let first = TBD<T>()
  for d in deferreds.shuffle()
  {
    d.notify {
      value in
      do { try first.determine(value) }
      catch { /* We don't care, it just means it's not the first completed */ }
    }
  }
  return first
}
