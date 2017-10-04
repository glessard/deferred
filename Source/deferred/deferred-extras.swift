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

extension Deferred
{
  // MARK: onValue: execute a task when (and only when) a computation succeeds

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes determined with a value
  /// The closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter task: the closure to be enqueued
  /// - parameter value: the value of the just-determined `Deferred`

  public func onValue(qos: DispatchQoS? = nil, task: @escaping (_ value: Value) -> Void)
  {
    notify(qos: qos) { $0.value.map(task) }
  }

  // MARK: onError: execute a task when (and only when) a computation fails

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes determined with an error
  /// The closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter task: the closure to be enqueued
  /// - parameter error: the error from the just-determined `Deferred`

  public func onError(qos: DispatchQoS? = nil, task: @escaping (_ error: Error) -> Void)
  {
    notify(qos: qos) { $0.error.map(task) }
  }
}

// MARK: map: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public func map<Other>(qos: DispatchQoS? = nil, transform: @escaping (_ value: Value) throws -> Other) -> Deferred<Other>
  {
    return Mapped<Other>(qos: qos, source: self, transform: transform)
  }
}

// MARK: flatMap: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public func flatMap<Other>(qos: DispatchQoS? = nil, transform: @escaping (_ value: Value) -> Deferred<Other>) -> Deferred<Other>
  {
    return Bind<Other>(qos: qos, source: self, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously if and when `self` becomes determined with an error.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter error: the Error to be transformed for a new `Deferred`

  public func recover(qos: DispatchQoS? = nil, transform: @escaping (_ error: Error) -> Deferred<Value>) -> Deferred<Value>
  {
    return Bind(qos: qos, source: self, transform: transform)
  }
}

extension Deferred
{
  /// Initialize a `Deferred` with a computation task to be performed in the background
  /// If at first it does not succeed, it will try `attempts` times in total before being determined with an `Error`.
  ///
  /// - parameter attempts: a maximum number of times to attempt `task`
  /// - parameter qos: the QoS at which the computation (and notifications) should be performed; defaults to the current QoS.
  /// - parameter task: the computation to be performed

  public static func RetryTask(_ attempts: Int, qos: DispatchQoS = .current,
                               task: @escaping () throws -> Value) -> Deferred
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    return Deferred.RetryTask(attempts, queue: queue, task: task)
  }

  /// Initialize a `Deferred` with a computation task to be performed in the background
  /// If at first it does not succeed, it will try `attempts` times in total before being determined with an `Error`.
  ///
  /// - parameter attempts: a maximum number of times to attempt `task`
  /// - parameter queue: the `DispatchQueue` on which the computation (and notifications) will be executed
  /// - parameter task: the computation to be performed

  public static func RetryTask(_ attempts: Int, queue: DispatchQueue,
                               task: @escaping () throws -> Value) -> Deferred
  {
    return Deferred.Retrying(attempts, queue: queue, task: { Deferred(queue: queue, task: task) })
  }

  /// Initialize a `Deferred` with a computation task to be performed in the background
  /// If at first it does not succeed, it will try `attempts` times in total before being determined with an `Error`.
  ///
  /// - parameter attempts: a maximum number of times to attempt `task`
  /// - parameter qos: the QoS at which the computation (and notifications) should be performed; defaults to the current QoS.
  /// - parameter task: the computation to be performed

  public static func Retrying(_ attempts: Int, qos: DispatchQoS = .current,
                              task: @escaping () -> Deferred) -> Deferred
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    return Deferred.Retrying(attempts, queue: queue, task: task)
  }

  /// Initialize a `Deferred` with a computation task to be performed in the background
  /// If at first it does not succeed, it will try `attempts` times in total before being determined with an `Error`.
  ///
  /// - parameter attempts: a maximum number of times to attempt `task`
  /// - parameter queue: the `DispatchQueue` on which the computation (and notifications) will be executed
  /// - parameter task: the computation to be performed

  public static func Retrying(_ attempts: Int, queue: DispatchQueue,
                              task: @escaping () -> Deferred) -> Deferred
  {
    guard attempts > 0 else
    {
      let error = DeferredError.invalid("task was not allowed a single attempt in \(#function)")
      return Deferred<Value>(queue: queue, error: error)
    }

    return (1..<attempts).reduce(task().enqueuing(on: queue)) {
      (deferred, _) in
      deferred.recover(transform: { _ in task() })
    }
  }
}

// MARK: apply: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become determined.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public func apply<Other>(qos: DispatchQoS? = nil, transform: Deferred<(_ value: Value) throws -> Other>) -> Deferred<Other>
  {
    return Applicator<Other>(qos: qos, source: self, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become determined.
  ///
  /// Adaptor made desirable by insufficient covariance from throwing to non-throwing closure types. (radar 22013315)
  /// (i.e. if the difference between the type signature of two closures is whether they throw,
  /// the non-throwing one should be usable anywhere the throwing one can.)
  /// Can hopefully be removed later.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public final func apply<Other>(qos: DispatchQoS? = nil, transform: Deferred<(_ value: Value) -> Other>) -> Deferred<Other>
  {
    let retransform = transform.map(qos: qos) { transform in { v throws in transform(v) } }
    return Applicator<Other>(qos: qos, source: self, transform: retransform)
  }
}

extension Deferred
{
  /// Insert a validation step in a chain of Deferred.
  /// Pass `Value` through if the predicate returns `true`, otherwise replace it with the error `DeferredError.invalid`.
  ///
  /// - parameter qos: the QOS class at which to execute the predicate; defaults to the QOS class of this Deferred's queue.
  /// - parameter predicate: a predicate that validates the passed-in `Value`.
  /// - returns: a `Deferred` reference holding a validated `Value`
  /// - parameter value: the value to be validated

  public final func validate(qos: DispatchQoS? = nil,
                             predicate: @escaping (_ value: Value) -> Bool, message: String = "") -> Deferred
  {
    return self.map(qos: qos) {
      value in
      guard predicate(value)
      else { throw DeferredError.invalid(message) }
      return value
    }
  }

  /// Insert a validation step in a chain of Deferred.
  /// Pass `Value` through if the predicate returns normally, otherwise replace it by the `Error` thrown by the predicate.
  ///
  /// - parameter qos: the QoS class at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter predicate: a closure that validates the passed-in `Value` by either returning normally or throwing
  /// - returns: a `Deferred` reference holding a validated `Value`
  /// - parameter value: the value to be validated

  public final func validate(qos: DispatchQoS? = nil,
                             predicate: @escaping (_ value: Value) throws -> Void) -> Deferred
  {
    return self.map(qos: qos) {
      value in
      try predicate(value)
      return value
    }
  }
}

extension Optional
{
  /// Create a `Deferred` from this `Optional`.
  /// If `optional` is `nil` then `Deferred` will be determined with the error `DeferredError.invalid`
  ///
  /// - parameter queue: the dispatch queue upon which to execute notifications for the new `Deferred`

  public func deferred(queue: DispatchQueue) -> Deferred<Wrapped>
  {
    switch self
    {
    case .some(let value):
      return Deferred(queue: queue, value: value)
    case .none:
      return Deferred(queue: queue, error: DeferredError.invalid("initialized from a nil Optional"))
    }
  }

  /// Create a `Deferred` from this `Optional`.
  /// If `optional` is `nil` then `Deferred` will be determined with the error `DeferredError.invalid`
  ///
  /// - parameter qos: the Quality-of-Service class at which to perform notifications for the new `Deferred`

  public func deferred(qos: DispatchQoS = .current) -> Deferred<Wrapped>
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    return self.deferred(queue: queue)
  }
}
