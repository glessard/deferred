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
    return timeout(ns: µs*1000, reason: reason)
  }

  /// Return a `Deferred` whose determination will occur at most `ms` milliseconds from the time of evaluation.
  /// If `self` has not become determined after the timeout delay, the new `Deferred` will be determined in an error state, `DeferredError.Canceled`.
  /// - parameter ms: a number of milliseconds
  /// - returns: a `Deferred` reference

  public func timeout(ms ms: Int, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    return timeout(ns: ms*1_000_000, reason: reason)
  }

  /// Return a `Deferred` whose determination will occur at most a number of seconds from the time of evaluation.
  /// If `self` has not become determined after the timeout delay, the new `Deferred` will be determined in an error state, `DeferredError.Canceled`.
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - returns: a `Deferred` reference

  public func timeout(seconds s: Double, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    return timeout(ns: Int(s*1e9), reason: reason)
  }

  /// Return a `Deferred` whose determination will occur at most `ns` nanoseconds from the time of evaluation.
  /// - parameter ns: a number of nanoseconds
  /// - returns: a `Deferred` reference

  public func timeout(ns ns: Int, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    if self.isDetermined { return self }

    if ns > 0
    {
      let queue = dispatch_get_global_queue(qos_class_self(), 0)
      let timeout = dispatch_time(DISPATCH_TIME_NOW, Int64(ns))

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
    return Deferred<U>(queue: queue, qos: qos, source: self, transform: transform)
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
    return Deferred<U>(queue: queue, qos: qos, source: self, transform: transform)
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
    return Deferred<U>(queue: queue, qos: qos, source: self, transform: transform)
  }
}

// MARK: apply: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become determined.
  /// The transforming closure will be enqueued on the global queue at the current quality of service class.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func apply<U>(transform: Deferred<(T)throws->U>) -> Deferred<U>
  {
    return apply(dispatch_get_global_queue(qos_class_self(), 0), transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become determined.
  /// The transforming closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the quality-of-service to associate with the closure
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func apply<U>(qos: qos_class_t, transform: Deferred<(T)throws->U>) -> Deferred<U>
  {
    return apply(dispatch_get_global_queue(qos, 0), transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become determined.
  /// - parameter queue: the `dispatch_queue_t` onto which the computation should be queued
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func apply<U>(queue: dispatch_queue_t, qos: qos_class_t = QOS_CLASS_UNSPECIFIED, transform: Deferred<(T)throws->U>) -> Deferred<U>
  {
    return Deferred<U>(queue: queue, qos: qos, source: self, transform: transform)
  }
}

// combine two or more Deferred objects into one.

extension Deferred
{
  /// Combine `self` with another `Deferred` into a new `Deferred`.
  /// The returned `Deferred` will become determined after both `self` and `other` are determined.
  ///
  /// Equivalent to but hopefully more efficient than:
  /// ```
  /// Deferred { (self.value, other.value) }
  /// ```
  /// - parameter other: a second `Deferred` to combine with `self`
  /// - returns: a new `Deferred` whose value is a tuple of `self.value` and `other.value`

  public func combine<U>(other: Deferred<U>) -> Deferred<(T,U)>
  {
    return flatMap { (t: T) in other.map { (u: U) in (t,u) } }
  }

  /// Combine `self` with two other `Deferred`s into a new `Deferred`.
  /// The returned `Deferred` will become determined after all three input `Deferred`s are determined.
  /// - parameter o1: another `Deferred` to combine with `self`
  /// - parameter o2: another `Deferred` to combine with `self`
  /// - returns: a new `Deferred` whose value is a tuple of `self.value`, `o1.value` and `o2.value`

  public func combine<U1,U2>(o1: Deferred<U1>, _ o2: Deferred<U2>) -> Deferred<(T,U1,U2)>
  {
    return combine(o1).flatMap { (t,u1) in o2.map { u2 in (t,u1,u2) } }
  }

  /// Combine `self` with three other `Deferred`s into a new `Deferred`.
  /// The returned `Deferred` will become determined after all three input `Deferred`s are determined.
  /// - parameter o1: another `Deferred` to combine with `self`
  /// - parameter o2: another `Deferred` to combine with `self`
  /// - parameter o3: another `Deferred` to combine with `self`
  /// - returns: a new `Deferred` whose value is a tuple of `self.value`, `o1.value`, `o2.value` and `o3.value`

  public func combine<U1,U2,U3>(o1: Deferred<U1>, _ o2: Deferred<U2>, _ o3: Deferred<U3>) -> Deferred<(T,U1,U2,U3)>
  {
    return combine(o1,o2).flatMap { (t,u1,u2) in o3.map { u3 in (t,u1,u2,u3) } }
  }
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
