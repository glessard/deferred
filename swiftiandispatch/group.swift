//
//  group.swift
//  swiftiandispatch
//
//  Created by Guillaume Lessard on 2015-03-05.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  This makes using dispatch_group_t somewhat more Swiftian.
*/

// MARK: Waiting on group
public extension dispatch_group_t
{
  public final func wait(until: dispatch_time_t = DISPATCH_TIME_FOREVER)
  {
    dispatch_group_wait(self, until)
  }

  public final func wait(forSeconds s: Double)
  {
    dispatch_group_wait(self, dispatch_time(DISPATCH_TIME_NOW, Int64(s*1e9)))
  }
}

// MARK: Asynchronous tasks tied to group
public extension dispatch_group_t
{
  public func async(task: () -> ())
  {
    dispatch_group_async(self, dispatch_get_global_queue(qos_class_self(), 0), task)
  }

  public func async(qos: qos_class_t, task: () -> ())
  {
    dispatch_group_async(self, dispatch_get_global_queue(qos, 0), task)
  }

  public func async(#queue: dispatch_queue_t, task: () -> ())
  {
    // without naming the #queue parameter, this would inadvertently
    // redeclare a method that is otherwise not visible from Swift
    dispatch_group_async(self, queue, task)
  }

  public func async<T>(task: () -> T) -> Result<T>
  {
    return async(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func async<T>(qos: qos_class_t, task: () -> T) -> Result<T>
  {
    return async(dispatch_get_global_queue(qos, 0), task: task)
  }

  public func async<T>(queue: dispatch_queue_t, task: () -> T) -> Result<T>
  {
    let g = dispatch_group_create()!
    var result: T! = nil

    dispatch_group_enter(g)
    dispatch_group_async(self, queue) {
      result = task()
      dispatch_group_leave(g)
    }

    return Result(group: g) {
      () -> T in
      dispatch_group_wait(g, DISPATCH_TIME_FOREVER)
      return result
    }
  }
}

// MARK: Notify on group completion
extension dispatch_group_t
{
  public final func notify(task: () -> ())
  {
    dispatch_group_notify(self, dispatch_get_global_queue(qos_class_self(), 0), task)
  }

  public final func notify(qos: qos_class_t, task: () -> ())
  {
    dispatch_group_notify(self, dispatch_get_global_queue(qos, 0), task)
  }

  public final func notify(#queue: dispatch_queue_t, task: () -> ())
  {
    // without naming the #queue parameter, this would inadvertently
    // redeclare a method that is otherwise not visible from Swift
    dispatch_group_notify(self, queue, task)
  }

  public func notify<T>(task: () -> T) -> Result<T>
  {
    return notify(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func notify<T>(qos: qos_class_t, task: () -> T) -> Result<T>
  {
    return notify(dispatch_get_global_queue(qos, 0), task: task)
  }

  public func notify<T>(queue: dispatch_queue_t, task: () -> T) -> Result<T>
  {
    let g = dispatch_group_create()!
    var result: T! = nil

    dispatch_group_enter(g)
    dispatch_group_notify(self, queue) {
      result = task()
      dispatch_group_leave(g)
    }

    return Result<T>(group: g) {
      () -> T in
      dispatch_group_wait(g, DISPATCH_TIME_FOREVER)
      return result
    }
  }
}
