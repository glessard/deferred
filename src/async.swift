//
//  async.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/// Utility shortcut for Grand Central Dispatch
///
/// Example:
/// ```
/// async { println("In the background") }
/// ```
/// is simply a shortcut for
/// ```
/// dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) { println("In the background") }
/// ```
/// Much less wordy.
///
/// A queue or a qos_class_t can be provided as a parameter in addition to the closure.
/// When none is supplied, the global queue at the current qos class will be used.
/// In all cases, a dispatch_group_t may be associated with the block to be executed.
///
/// - parameter task: a block to be executed asynchronously.

public func async(task: () -> Void)
{
  dispatch_async(dispatch_get_global_queue(qos_class_self(), 0), task)
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter group: a `dispatch_group_t` to associate to this block execution
/// - parameter task: a block to be executed asynchronously

public func async(group group: dispatch_group_t, task: () -> Void)
{
  dispatch_group_async(group, dispatch_get_global_queue(qos_class_self(), 0), task)
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter qos: the quality-of-service class to associate to this block
/// - parameter task: a block to be executed asynchronously

public func async(qos: qos_class_t, task: () -> Void)
{
  dispatch_async(dispatch_get_global_queue(qos, 0), task)
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter qos: the quality-of-service class to associate to this block
/// - parameter group: a `dispatch_group_t` to associate to this block execution
/// - parameter task: a block to be executed asynchronously

public func async(qos: qos_class_t, group: dispatch_group_t, task: () -> Void)
{
  dispatch_group_async(group, dispatch_get_global_queue(qos, 0), task)
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter queue: the `dispatch_queue_t` onto which the block should be added for execution
/// - parameter task: a block to be executed asynchronously

public func async(queue: dispatch_queue_t, task: () -> Void)
{
  dispatch_async(queue, task)
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter queue: the `dispatch_queue_t` onto which the block should be added for execution
/// - parameter group: a `dispatch_group_t` to associate to this block execution
/// - parameter task: a block to be executed asynchronously

public func async(queue: dispatch_queue_t, group: dispatch_group_t, task: () -> Void)
{
  dispatch_group_async(group, queue, task)
}
