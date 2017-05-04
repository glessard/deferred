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
  /// - parameter qos: the quality of service class at which the parallel task should be performed
  /// - parameter task: the computation to be performed in parallel; the closure takes an index as its parameter
  /// - returns: an array of `Deferred`

  public static func inParallel(count: Int, qos: DispatchQoS = DispatchQoS.current ?? .default,
                                task: @escaping (Int) throws -> Value) -> [Deferred<Value>]
  {
    return (0..<count).deferredMap(qos: qos, task: task)
  }

  /// Initialize an array of `Deferred` to be computed in parallel, on the desired dispatch queue
  ///
  /// - parameter count: the number of parallel tasks to perform
  /// - parameter queue: the `DispatchQueue` onto which the parallel task should be performed.
  /// - parameter task: the computation to be performed in parallel; the closure takes an index as its parameter
  /// - returns: an array of `Deferred`

  public static func inParallel(count: Int, queue: DispatchQueue, task: @escaping (Int) throws -> Value) -> [Deferred<Value>]
  {
    return (0..<count).deferredMap(queue: queue, task: task)
  }
}

extension Collection where Index == Indices.Iterator.Element
{
  /// Map a collection to an array of `Deferred` to be computed in parallel, at the desired quality of service level
  ///
  /// - parameter qos: the quality of service class at which the parallel task should be performed
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`

  public func deferredMap<Value>(qos: DispatchQoS = DispatchQoS.current ?? .default,
                                 task: @escaping (Self.Iterator.Element) throws -> Value) -> [Deferred<Value>]
  {
    return deferredMap(queue: DispatchQueue.global(qos: qos.qosClass), task: task)
  }

  /// Map a collection to an array of `Deferred` to be computed in parallel, on the desired dispatch queue
  ///
  /// - parameter queue: the `DispatchQueue` on which the parallel task should be performed.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`

  public func deferredMap<Value>(queue: DispatchQueue, task: @escaping (Self.Iterator.Element) throws -> Value) -> [Deferred<Value>]
  {
    let count: Int = numericCast(self.count)
    let deferreds = (0..<count).map { _ in TBD<Value>(queue: queue) }
    let indexList = Array(self.indices)

    queue.async {
      DispatchQueue.concurrentPerform(iterations: count) {
        iteration in
        deferreds[iteration].beginExecution()
        let result = Result { try task(self[indexList[iteration]]) }
        deferreds[iteration].determine(result) // an error here means `deferred[index]` has been canceled
      }
    }
    return deferreds
  }
}
