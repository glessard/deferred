//
//  deferred-parallel.swift
//  deferred
//
//  Created by Guillaume Lessard on 2015-11-06.
//  Copyright © 2015-2020 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension Deferred where Failure == Error
{
  /// Initialize an array of `Deferred` to be computed in parallel, at the desired QoS level
  ///
  /// - parameter count: the number of parallel tasks to perform
  /// - parameter qos: the QoS at which the parallel task should be performed; defaults to the current QoS class.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`
  /// - parameter index: an index for the computation

  public static func inParallel(count: Int, qos: DispatchQoS = .current,
                                task: @escaping (_ index: Int) throws -> Success) -> [Deferred<Success, Failure>]
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
                                task: @escaping (_ index: Int) throws -> Success) -> [Deferred<Success, Failure>]
  {
    return (0..<count).deferredMap(queue: queue, task: task)
  }
}

extension Deferred where Failure == Never
{
  /// Initialize an array of `Deferred` to be computed in parallel, at the desired QoS level
  ///
  /// - parameter count: the number of parallel tasks to perform
  /// - parameter qos: the QoS at which the parallel task should be performed; defaults to the current QoS class.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`
  /// - parameter index: an index for the computation

  public static func inParallel(count: Int, qos: DispatchQoS = .current,
                                task: @escaping (_ index: Int) -> Success) -> [Deferred<Success, Failure>]
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
                                task: @escaping (_ index: Int) -> Success) -> [Deferred<Success, Failure>]
  {
    return (0..<count).deferredMap(queue: queue, task: task)
  }
}

extension Collection
{
  /// Map a collection to an array of `Deferred` to be computed in parallel, at the desired QoS level
  ///
  /// - parameter qos: the QoS at which the parallel task should be performed; defaults to the current QoS class.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`
  /// - parameter element: an element to transform into a new `Deferred`

  public func deferredMap<Success>(qos: DispatchQoS = .current,
                                   task: @escaping (_ element: Self.Element) throws -> Success) -> [Deferred<Success, Error>]
  {
    let queue = DispatchQueue(label: "deferred-map", qos: qos)
    return deferredMap(queue: queue, task: task)
  }

  /// Map a collection to an array of `Deferred` to be computed in parallel, at the desired QoS level
  ///
  /// - parameter qos: the QoS at which the parallel task should be performed; defaults to the current QoS class.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`
  /// - parameter element: an element to transform into a new `Deferred`

  public func deferredMap<Success>(qos: DispatchQoS = .current,
                                   task: @escaping (_ element: Self.Element) -> Success) -> [Deferred<Success, Never>]
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

  public func deferredMap<Success>(queue: DispatchQueue,
                                   task: @escaping (_ element: Self.Element) throws -> Success) -> [Deferred<Success, Error>]
  {
    let count = self.count
    let pairs = (0..<count).map {
      Deferred<Success, Error>.CreatePair(
        queue: DispatchQueue(label: "deferred-map-\($0)", qos: queue.qos, target: queue)
      )
    }
    let resolvers = pairs.map { $0.0 }

    queue.async {
      DispatchQueue.concurrentPerform(iterations: count) {
        iteration in
        let d = resolvers[iteration]
        d.beginExecution()
        let index = self.index(self.startIndex, offsetBy: iteration)
        do {
          let value = try task(self[index])
          d.resolve(value: value)
        }
        catch {
          d.resolve(error: error)
        }
      }
    }
    return pairs.map { $0.1 }
  }

  /// Map a collection to an array of `Deferred` to be computed in parallel, on the desired dispatch queue
  ///
  /// - parameter queue: the `DispatchQueue` on which the parallel task should be performed.
  /// - parameter task: the computation to be performed in parallel
  /// - returns: an array of `Deferred`
  /// - parameter element: an element to transform into a new `Deferred`

  public func deferredMap<Success>(queue: DispatchQueue,
                                   task: @escaping (_ element: Self.Element) -> Success) -> [Deferred<Success, Never>]
  {
    let count = self.count
    let pairs = (0..<count).map {
      Deferred<Success, Never>.CreatePair(
        queue: DispatchQueue(label: "deferred-map-\($0)", qos: queue.qos, target: queue)
      )
    }
    let resolvers = pairs.map { $0.0 }

    queue.async {
      DispatchQueue.concurrentPerform(iterations: count) {
        iteration in
        let d = resolvers[iteration]
        d.beginExecution()
        let index = self.index(self.startIndex, offsetBy: iteration)
        d.resolve(value: task(self[index]))
      }
    }
    return pairs.map { $0.1 }
  }
}
