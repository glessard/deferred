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

// MARK: minimum delay until a `Deferred` has a value

extension Deferred
{
  /// Return a `Deferred` whose determination will occur at least `µs` microseconds from the time of evaluation.
  /// - parameter µs: a number of microseconds
  /// - returns: a `Deferred` reference

  public func delay(µs µs: Int) -> Deferred
  {
    return delay64(ns: Int64(µs)*1000)
  }

  /// Return a `Deferred` whose determination will occur at least `ms` milliseconds from the time of evaluation.
  /// - parameter ms: a number of milliseconds
  /// - returns: a `Deferred` reference

  public func delay(ms ms: Int) -> Deferred
  {
    return delay64(ns: Int64(ms)*1_000_000)
  }

  /// Return a `Deferred` whose determination will occur at least a number of seconds from the time of evaluation.
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - returns: a `Deferred` reference

  public func delay(seconds s: Double) -> Deferred
  {
    return delay64(ns: Int64(s*1e9))
  }

  /// Return a `Deferred` whose determination will occur at least `ns` nanoseconds from the time of evaluation.
  /// - parameter ns: a number of nanoseconds
  /// - returns: a `Deferred` reference

  public func delay(ns ns: Int) -> Deferred
  {
    return delay64(ns: Int64(ns))
  }

  private func delay64(ns ns: Int64) -> Deferred
  {
    if ns < 0 { return self }

    let queue = dispatch_get_global_queue(qos_class_self(), 0)
    let until = dispatch_time(DISPATCH_TIME_NOW, ns)
    return Delayed(queue: queue, source: self, until: until)
  }
}

// MARK: maximum time until a `Deferred` becomes determined

private let DefaultTimeoutMessage = "Operation timed out"

extension Deferred
{
  /// Return a `Deferred` whose determination will occur at most `µs` microseconds from the time of evaluation.
  /// If `self` has not become determined after the timeout delay, the new `Deferred` will be determined in an error state, `DeferredError.Canceled`.
  /// - parameter µs: a number of microseconds
  /// - returns: a `Deferred` reference

  public func timeout(µs µs: Int, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    return timeout64(ns: Int64(µs)*1000, reason: reason)
  }

  /// Return a `Deferred` whose determination will occur at most `ms` milliseconds from the time of evaluation.
  /// If `self` has not become determined after the timeout delay, the new `Deferred` will be determined in an error state, `DeferredError.Canceled`.
  /// - parameter ms: a number of milliseconds
  /// - returns: a `Deferred` reference

  public func timeout(ms ms: Int, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    return timeout64(ns: Int64(ms)*1_000_000, reason: reason)
  }

  /// Return a `Deferred` whose determination will occur at most a number of seconds from the time of evaluation.
  /// If `self` has not become determined after the timeout delay, the new `Deferred` will be determined in an error state, `DeferredError.Canceled`.
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - returns: a `Deferred` reference

  public func timeout(seconds s: Double, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    return timeout64(ns: Int64(s*1e9), reason: reason)
  }

  /// Return a `Deferred` whose determination will occur at most `ns` nanoseconds from the time of evaluation.
  /// - parameter ns: a number of nanoseconds
  /// - returns: a `Deferred` reference

  public func timeout(ns ns: Int, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    return timeout64(ns: Int64(ns), reason: reason)
  }

  private func timeout64(ns ns: Int64, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    if self.isDetermined { return self }

    if ns > 0
    {
      let queue = dispatch_get_global_queue(qos_class_self(), 0)
      let timeout = dispatch_time(DISPATCH_TIME_NOW, ns)

      let perishable = map(queue) { $0 }
      dispatch_after(timeout, queue) { perishable.cancel(reason) }
      return perishable
    }

    return Deferred(error: DeferredError.Canceled(reason))
  }
}

// MARK: onValue: execute a task when (and only when) a computation succeeds

extension Deferred
{
  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes determined with a value
  /// The closure will be enqueued on the global queue at the current quality of service class.
  /// - parameter task: the closure to be enqueued

  public func onValue(task: (T) -> Void)
  {
    onValue(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes determined with a value
  /// The closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the quality-of-service to associate with the closure
  /// - parameter task: the closure to be enqueued

  public func onValue(qos: qos_class_t, task: (T) -> Void)
  {
    onValue(dispatch_get_global_queue(qos, 0), task: task)
  }

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes determined with a value
  /// The closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter queue: the `dispatch_queue_t` onto which the closure should be queued
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter task: the closure to be enqueued

  public func onValue(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, task: (T) -> Void)
  {
    notify(queue, qos: qos) { if let value = $0.value { task(value) } }
  }
}

// MARK: onError: execute a task when (and only when) a computation fails

extension Deferred
{
  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes determined with an error
  /// The closure will be enqueued on the global queue at the current quality of service class.
  /// - parameter task: the closure to be enqueued

  public func onError(task: (ErrorType) -> Void)
  {
    onError(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes determined with an error
  /// The closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the quality-of-service to associate with the closure
  /// - parameter task: the closure to be enqueued

  public func onError(qos: qos_class_t, task: (ErrorType) -> Void)
  {
    onError(dispatch_get_global_queue(qos, 0), task: task)
  }

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes determined with an error
  /// The closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter queue: the `dispatch_queue_t` onto which the closure should be queued
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter task: the closure to be enqueued

  public func onError(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, task: (ErrorType) -> Void)
  {
    notify(queue, qos: qos) { if let error = $0.error { task(error) } }
  }
}

// MARK: execute a transform upon determination as an error -- map for the ErrorType path.

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously if and when `self` becomes determined with an error.
  /// The transforming closure will be enqueued on the global queue at the current quality of service class.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func recover(transform: (ErrorType) throws -> T) -> Deferred<T>
  {
    return recover(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously if and when `self` becomes determined with an error.
  /// The transforming closure will be enqueued on the global queue at the current quality of service class.
  /// - parameter qos: the quality-of-service to associate with the closure
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func recover(qos: qos_class_t, transform: (ErrorType) throws -> T) -> Deferred<T>
  {
    return recover(dispatch_get_global_queue(qos, 0), transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously if and when `self` becomes determined with an error.
  /// The transforming closure will be enqueued on the global queue at the current quality of service class.
  /// - parameter queue: the `dispatch_queue_t` onto which the closure should be queued
  /// - parameter qos: the quality-of-service to associate with the closure
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func recover(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, transform: (ErrorType) throws -> T) -> Deferred<T>
  {
    return Mapped(queue: queue, qos: qos, source: self, transform: transform)
  }
}

// MARK: enqueue a closure which takes the result of a `Deferred`

extension Deferred
{
  /// Enqueue a closure to be performed asynchronously after `self` becomes determined.
  /// The closure will be enqueued on the global queue at the current quality of service class.
  /// - parameter task: the closure to be enqueued

  public func notify(task: (Result<T>) -> Void)
  {
    notify(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  /// Enqueue a closure to be performed asynchronously after `self` becomes determined.
  /// The closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the quality-of-service to associate with the closure
  /// - parameter task: the closure to be enqueued

  public func notify(qos: qos_class_t, task: (Result<T>) -> Void)
  {
    notify(dispatch_get_global_queue(qos, 0), task: task)
  }
}

// MARK: map: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// The transforming closure will be enqueued on the global queue at the current quality of service class.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func map<U>(transform: (T) throws -> U) -> Deferred<U>
  {
    return map(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// The transforming closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the quality-of-service to associate with the closure
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func map<U>(qos: qos_class_t, transform: (T) throws -> U) -> Deferred<U>
  {
    return map(dispatch_get_global_queue(qos, 0), transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// - parameter queue: the `dispatch_queue_t` onto which the computation should be queued
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func map<U>(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, transform: (T) throws -> U) -> Deferred<U>
  {
    return Mapped<U>(queue: queue, qos: qos, source: self, transform: transform)
  }
}

// MARK: flatMap: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// The transforming closure will be enqueued on the global queue at the current quality of service class.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func flatMap<U>(transform: (T) -> Deferred<U>) -> Deferred<U>
  {
    return flatMap(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// The transforming closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the quality-of-service to associate with the closure
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func flatMap<U>(qos: qos_class_t, transform: (T) -> Deferred<U>) -> Deferred<U>
  {
    return flatMap(dispatch_get_global_queue(qos, 0), transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// - parameter queue: the `dispatch_queue_t` onto which the computation should be queued
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func flatMap<U>(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, transform: (T) -> Deferred<U>) -> Deferred<U>
  {
    return Mapped<U>(queue: queue, qos: qos, source: self, transform: transform)
  }
}

// MARK: flatMap: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// The transforming closure will be enqueued on the global queue at the current quality of service class.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func flatMap<U>(transform: (T) -> Result<U>) -> Deferred<U>
  {
    return flatMap(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// The transforming closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the quality-of-service to associate with the closure
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func flatMap<U>(qos: qos_class_t, transform: (T) -> Result<U>) -> Deferred<U>
  {
    return flatMap(dispatch_get_global_queue(qos, 0), transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// - parameter queue: the `dispatch_queue_t` onto which the computation should be queued
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func flatMap<U>(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, transform: (T) -> Result<U>) -> Deferred<U>
  {
    return Mapped<U>(queue: queue, qos: qos, source: self, transform: transform)
  }
}

// MARK: apply: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Adaptor made desirable by insufficient covariance between throwing and non-throwing functions.
  /// Should remove later.

  public func apply<U>(transform: Deferred<(T) -> U>) -> Deferred<U>
  {
    let throwing = transform.map { transform in { (t:T) throws -> U in transform(t) } }
    return apply(dispatch_get_global_queue(qos_class_self(), 0), transform: throwing)
  }

  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become determined.
  /// The transforming closure will be enqueued on the global queue at the current quality of service class.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func apply<U>(transform: Deferred<(T) throws -> U>) -> Deferred<U>
  {
    return apply(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become determined.
  /// The transforming closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the quality-of-service to associate with the closure
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func apply<U>(qos: qos_class_t, transform: Deferred<(T) throws -> U>) -> Deferred<U>
  {
    return apply(dispatch_get_global_queue(qos, 0), transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become determined.
  /// - parameter queue: the `dispatch_queue_t` onto which the computation should be queued
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func apply<U>(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, transform: Deferred<(T) throws -> U>) -> Deferred<U>
  {
    return Applicator<U>(queue: queue, qos: qos, source: self, transform: transform)
  }
}

// combine two or more Deferred objects into one.

/// Combine two `Deferred` into one.
/// The returned `Deferred` will become determined after both inputs are determined.
///
/// Equivalent to but hopefully more efficient than:
/// ```
/// Deferred { (d1.value, d2.value) }
/// ```
/// - parameter d1: a `Deferred`
/// - parameter d2: a second `Deferred` to combine with `d1`
/// - returns: a new `Deferred` whose value shall be a tuple of `d1.value` and `d2.value`

public func combine<T1,T2>(d1: Deferred<T1>, _ d2: Deferred<T2>) -> Deferred<(T1,T2)>
{
  return d1.flatMap { t1 in d2.map { t2 in (t1,t2) } }
}

public func combine<T1,T2,T3>(d1: Deferred<T1>, _ d2: Deferred<T2>, _ d3: Deferred<T3>) -> Deferred<(T1,T2,T3)>
{
  return combine(d1,d2).flatMap { (t1,t2) in d3.map { t3 in (t1,t2,t3) } }
}

public func combine<T1,T2,T3,T4>(d1: Deferred<T1>, _ d2: Deferred<T2>, _ d3: Deferred<T3>, _ d4: Deferred<T4>) -> Deferred<(T1,T2,T3,T4)>
{
  return combine(d1,d2,d3).flatMap { (t1,t2,t3) in d4.map { t4 in (t1,t2,t3,t4) } }
}

/// Combine an array of `Deferred`s into a new `Deferred` whose value is an array.
/// The returned `Deferred` will become determined after every input `Deferred` is determined.
///
/// Equivalent to but hopefully more efficient than:
/// ```
/// Deferred { deferreds.map { $0.value } }
/// ```
/// - parameter deferreds: an array of `Deferred`
/// - returns: a new `Deferred`

public func combine<T>(deferreds: [Deferred<T>]) -> Deferred<[T]>
{
  return deferreds.reduce(Deferred<[T]>(value: [])) {
    (accumulator, element) in
    element.flatMap {
      value in
      accumulator.map {
        values in
        return values + [value]
      }
    }
  }
}

/// Return the value of the first of an array of `Deferred`s to be determined.
/// Note that if the array is empty the resulting `Deferred` can never become determined.
///
/// - parameter deferreds: an array of `Deferred`
/// - returns: a new `Deferred`

public func firstValue<T>(deferreds: [Deferred<T>]) -> Deferred<T>
{
  let first = TBD<T>()
  deferreds.shuffle().forEach {
    $0.notify {
      result in
      _ = try? first.determine(result) // an error here just means this wasn't the first completed result
    }
  }
  return first
}

/// Return the first of an array of `Deferred`s to become determined.
/// Note that if the array is empty the resulting `Deferred` can never become determined.
///
/// - parameter deferreds: an array of `Deferred`
/// - returns: a new `Deferred`

public func firstDetermined<T>(deferreds: [Deferred<T>]) -> Deferred<Deferred<T>>
{
  let first = TBD<Deferred<T>>()
  deferreds.shuffle().forEach {
    deferred in
    deferred.notify {
      _ in
      _ = try? first.determine(deferred) // an error here just means this wasn't the first determined deferred
    }
  }
  return first
}


extension Deferred
{
  public static func inParallel(count count: Int, _ task: (index: Int) throws -> T) -> [Deferred<T>]
  {
    return (0..<count).deferredMap(task)
  }

  public static func inParallel(count count: Int, qos: qos_class_t, task: (index: Int) throws -> T) -> [Deferred<T>]
  {
    return (0..<count).deferredMap(qos, task: task)
  }

  public static func inParallel(count count: Int, queue: dispatch_queue_t, task: (index: Int) throws -> T) -> [Deferred<T>]
  {
    return (0..<count).deferredMap(queue, task: task)
  }
}

extension CollectionType
{
  public func deferredMap<T>(task: (Self.Generator.Element) throws -> T) -> [Deferred<T>]
  {
    return deferredMap(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func deferredMap<T>(qos: qos_class_t, task: (Self.Generator.Element) throws -> T) -> [Deferred<T>]
  {
    return deferredMap(dispatch_get_global_queue(qos, 0), task: task)
  }

  public func deferredMap<T>(queue: dispatch_queue_t, task: (Self.Generator.Element) throws -> T) -> [Deferred<T>]
  {
    // The following 2 lines exist to get around the fact that Self.Index.Distance does not convert to Int.
    let indices = Array(self.indices)
    let count = indices.count

    let deferreds = (indices).map { _ in TBD<T>() }
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
