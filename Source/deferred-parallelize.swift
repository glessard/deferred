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
  /// Initialize an array of `Deferred` to be computed in parallel, at the desired quality of service level
  ///
  /// - parameter count: the number of parallel tasks to perform
  /// - parameter qos: the desired quality of service class for the new `Deferred` objects
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`

  public static func inParallel(count: Int, qos: DispatchQoS = .unspecified, task: (index: Int) throws -> Value) -> [Deferred<Value>]
  { // FIXME: default qos value should be equivalent to qos_class_self()
    return (0..<count).deferredMap(qos: qos, task: task)
  }

  /// Initialize an array of `Deferred` to be computed in parallel, on the desired dispatch queue
  ///
  /// - parameter count: the number of parallel tasks to perform
  /// - parameter queue: the `dispatch_queue` onto which the `Deferreds` should be performed.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`

  public static func inParallel(count: Int, queue: DispatchQueue, task: (index: Int) throws -> Value) -> [Deferred<Value>]
  {
    return (0..<count).deferredMap(queue: queue, task: task)
  }
}

extension Collection where Self.Indices.Iterator.Element == Self.Index
{
  /// Map a collection to an array of `Deferred` to be computed in parallel, at the desired quality of service level
  ///
  /// - parameter qos: the desired quality of service class for the new `Deferred` objects
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`

  public func deferredMap<Value>(qos: DispatchQoS = .unspecified, task: (Self.Iterator.Element) throws -> Value) -> [Deferred<Value>]
  { // FIXME: default qos value should be equivalent to qos_class_self()
    // FIXME: obtain queue at intended qos
    return deferredMap(queue: DispatchQueue.global(), task: task)
  }

  /// Map a collection to an array of `Deferred` to be computed in parallel, on the desired dispatch queue
  ///
  /// - parameter queue: the `dispatch_queue` onto which the `Deferreds` should be performed.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`

  public func deferredMap<Value>(queue: DispatchQueue, task: (Self.Iterator.Element) throws -> Value) -> [Deferred<Value>]
  {
    // The following 2 lines exist to get around the fact that Self.Index.Distance does not convert to Int.
    let indices = Array(self.indices)
    let count = indices.count

    let deferreds = indices.map { _ in TBD<Value>() }
    queue.async {
      DispatchQueue.concurrentPerform(iterations: count) {
        index in
        deferreds[index].beginExecution()
        let result = Result { try task(self[indices[index]]) }
        _ = try? deferreds[index].determine(result) // an error here means `deferred[index]` has been canceled
      }
    }
    return deferreds
  }
}
