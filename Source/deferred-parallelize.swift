//
//  deferred-parallel.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 06/11/2015.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension Deferred
{
  /// Initialize an array of `Deferred` to be computed in parallel, at the current quality of service level
  ///
  /// - parameter count: the number of parallel tasks to perform
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`

  public static func inParallel(count count: Int, task: (index: Int) throws -> Value) -> [Deferred<Value>]
  {
    return (0..<count).deferredMap(task)
  }

  /// Initialize an array of `Deferred` to be computed in parallel, at the desired quality of service level
  ///
  /// - parameter count: the number of parallel tasks to perform
  /// - parameter qos: the desired quality of service class for the new `Deferred` objects
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`

  public static func inParallel(count count: Int, qos: qos_class_t, task: (index: Int) throws -> Value) -> [Deferred<Value>]
  {
    return (0..<count).deferredMap(qos, task: task)
  }

  /// Initialize an array of `Deferred` to be computed in parallel, on the desired dispatch queue
  ///
  /// - parameter count: the number of parallel tasks to perform
  /// - parameter queue: the `dispatch_queue` onto which the `Deferreds` should be performed.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`

  public static func inParallel(count count: Int, queue: dispatch_queue_t, task: (index: Int) throws -> Value) -> [Deferred<Value>]
  {
    return (0..<count).deferredMap(queue, task: task)
  }
}

extension CollectionType
{
  /// Map a collection to an array of `Deferred` to be computed in parallel, at the current quality of service level
  ///
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`

  public func deferredMap<Value>(task: (Self.Generator.Element) throws -> Value) -> [Deferred<Value>]
  {
    return deferredMap(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  /// Map a collection to an array of `Deferred` to be computed in parallel, at the desired quality of service level
  ///
  /// - parameter qos: the desired quality of service class for the new `Deferred` objects
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`

  public func deferredMap<Value>(qos: qos_class_t, task: (Self.Generator.Element) throws -> Value) -> [Deferred<Value>]
  {
    return deferredMap(dispatch_get_global_queue(qos, 0), task: task)
  }

  /// Map a collection to an array of `Deferred` to be computed in parallel, on the desired dispatch queue
  ///
  /// - parameter queue: the `dispatch_queue` onto which the `Deferreds` should be performed.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`

  public func deferredMap<Value>(queue: dispatch_queue_t, task: (Self.Generator.Element) throws -> Value) -> [Deferred<Value>]
  {
    // The following 2 lines exist to get around the fact that Self.Index.Distance does not convert to Int.
    let indices = Array(self.indices)
    let count = indices.count

    let deferreds = (indices).map { _ in TBD<Value>() }
    dispatch_async(dispatch_get_global_queue(dispatch_queue_get_qos_class(queue, nil), 0)) {
      dispatch_apply(count, queue) {
        index in
        deferreds[index].beginExecution()
        let result = Result { try task(self[indices[index]]) }
        _ = try? deferreds[index].determine(result) // an error here means `deferred[index]` has been canceled
      }
    }
    return deferreds
  }
}
