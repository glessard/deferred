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
  /// - parameter qos: the QoS at which the parallel task should be performed
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`
  /// - parameter index: an index for the computation

  public static func inParallel(count: Int, qos: DispatchQoS = .current,
                                task: @escaping (_ index: Int) throws -> Value) -> [Deferred<Value>]
  {
    return (0..<count).deferredMap(qos: qos, task: task)
  }

  /// Initialize an array of `Deferred` to be computed in parallel, on the desired dispatch queue
  ///
  /// - parameter count: the number of parallel tasks to perform
  /// - parameter queue: the `DispatchQueue` onto which the parallel task should be performed.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`
  /// - parameter index: an index for the computation

  public static func inParallel(count: Int, queue: DispatchQueue,
                                task: @escaping (_ index: Int) throws -> Value) -> [Deferred<Value>]
  {
    return (0..<count).deferredMap(queue: queue, task: task)
  }
}

#if swift(>=3.2)
extension Collection
{
  /// Map a collection to an array of `Deferred` to be computed in parallel, at the desired quality of service level
  ///
  /// - parameter qos: the QoS at which the parallel task should be performed
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`
  /// - parameter element: an element to transform into a new `Deferred`

  public func deferredMap<Value>(qos: DispatchQoS = .current,
                                 task: @escaping (_ element: Self.Iterator.Element) throws -> Value) -> [Deferred<Value>]
  {
    let queue = DispatchQueue(label: "deferred-map", qos: qos)
    return deferredMap(queue: queue, task: task)
  }

  /// Map a collection to an array of `Deferred` to be computed in parallel, on the desired dispatch queue
  ///
  /// - parameter queue: the `DispatchQueue` on which the parallel task should be performed.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`
  /// - parameter element: an element to transform into a new `Deferred`

  public func deferredMap<Value>(queue: DispatchQueue,
                                 task: @escaping (_ element: Self.Iterator.Element) throws -> Value) -> [Deferred<Value>]
  {
    let count: Int = numericCast(self.count)
    let deferreds = (0..<count).map { _ in TBD<Value>(queue: queue) }
    let indexList = Array(self.indices)

    queue.async {
      DispatchQueue.concurrentPerform(iterations: count) {
        iteration in
        deferreds[iteration].beginExecution()
        do {
          let value = try task(self[indexList[iteration]])
          deferreds[iteration].determine(value)
        }
        catch {
          deferreds[iteration].determine(error)
        }
      }
    }
    return deferreds
  }
}
#else
extension Collection where Index == Indices.Iterator.Element
{
  /// Map a collection to an array of `Deferred` to be computed in parallel, at the desired quality of service level
  ///
  /// - parameter qos: the QoS at which the parallel task should be performed
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`
  /// - parameter element: an element to transform into a new `Deferred`

  public func deferredMap<Value>(qos: DispatchQoS = .current,
                                 task: @escaping (_ element: Self.Iterator.Element) throws -> Value) -> [Deferred<Value>]
  {
    let queue = DispatchQueue(label: "deferred-map", qos: qos)
    return deferredMap(queue: queue, task: task)
  }

  /// Map a collection to an array of `Deferred` to be computed in parallel, on the desired dispatch queue
  ///
  /// - parameter queue: the `DispatchQueue` on which the parallel task should be performed.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`
  /// - parameter element: an element to transform into a new `Deferred`

  public func deferredMap<Value>(queue: DispatchQueue,
                                 task: @escaping (_ element: Self.Iterator.Element) throws -> Value) -> [Deferred<Value>]
  {
    let count: Int = numericCast(self.count)
    let deferreds = (0..<count).map { _ in TBD<Value>(queue: queue) }
    let indexList = Array(self.indices)

    queue.async {
      DispatchQueue.concurrentPerform(iterations: count) {
        iteration in
        deferreds[iteration].beginExecution()
        do {
          let value = try task(self[indexList[iteration]])
          deferreds[iteration].determine(value)
        }
        catch {
          deferreds[iteration].determine(error)
        }
      }
    }
    return deferreds
  }
}
#endif
