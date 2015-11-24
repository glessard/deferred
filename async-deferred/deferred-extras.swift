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

  public final func delay(µs µs: Int) -> Deferred
  {
    return delay64(ns: Int64(µs)*1000)
  }

  /// Return a `Deferred` whose determination will occur at least `ms` milliseconds from the time of evaluation.
  /// - parameter ms: a number of milliseconds
  /// - returns: a `Deferred` reference

  public final func delay(ms ms: Int) -> Deferred
  {
    return delay64(ns: Int64(ms)*1_000_000)
  }

  /// Return a `Deferred` whose determination will occur at least a number of seconds from the time of evaluation.
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - returns: a `Deferred` reference

  public final func delay(seconds s: Double) -> Deferred
  {
    return delay64(ns: Int64(s*1e9))
  }

  /// Return a `Deferred` whose determination will occur at least `ns` nanoseconds from the time of evaluation.
  /// - parameter ns: a number of nanoseconds
  /// - returns: a `Deferred` reference

  public final func delay(ns ns: Int) -> Deferred
  {
    return delay64(ns: Int64(ns))
  }

  private func delay64(ns ns: Int64) -> Deferred
  {
    if ns < 0 { return self }
    return Delayed(source: self, until: dispatch_time(DISPATCH_TIME_NOW, ns))
  }
}

// MARK: maximum time until a `Deferred` becomes determined

private let DefaultTimeoutMessage = "Operation timed out"

extension Deferred
{
  /// Return a `Deferred` whose determination will occur at most `µs` microseconds from the time of evaluation.
  /// If `self` has not become determined after the timeout delay, the new `Deferred` will be canceled.
  /// - parameter µs: a number of microseconds
  /// - parameter reason: the reason for the cancelation if the operation times out. Defaults to "Operation timed out".
  /// - returns: a `Deferred` reference

  public final func timeout(µs µs: Int, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    return timeout64(ns: Int64(µs)*1000, reason: reason)
  }

  /// Return a `Deferred` whose determination will occur at most `ms` milliseconds from the time of evaluation.
  /// If `self` has not become determined after the timeout delay, the new `Deferred` will be canceled.
  /// - parameter ms: a number of milliseconds
  /// - parameter reason: the reason for the cancelation if the operation times out. Defaults to "Operation timed out".
  /// - returns: a `Deferred` reference

  public final func timeout(ms ms: Int, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    return timeout64(ns: Int64(ms)*1_000_000, reason: reason)
  }

  /// Return a `Deferred` whose determination will occur at most a number of seconds from the time of evaluation.
  /// If `self` has not become determined after the timeout delay, the new `Deferred` will be canceled.
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - parameter reason: the reason for the cancelation if the operation times out. Defaults to "Operation timed out".
  /// - returns: a `Deferred` reference

  public final func timeout(seconds s: Double, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    return timeout64(ns: Int64(s*1e9), reason: reason)
  }

  /// Return a `Deferred` whose determination will occur at most `ns` nanoseconds from the time of evaluation.
  /// If `self` has not become determined after the timeout delay, the new `Deferred` will be canceled.
  /// - parameter ns: a number of nanoseconds
  /// - parameter reason: the reason for the cancelation if the operation times out. Defaults to "Operation timed out".
  /// - returns: a `Deferred` reference

  public final func timeout(ns ns: Int, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    return timeout64(ns: Int64(ns), reason: reason)
  }

  @inline(__always) private func timeout64(ns ns: Int64, reason: String) -> Deferred
  {
    if self.isDetermined { return self }
    return Timeout(source: self, timeout: ns, reason: reason)
  }
}

extension Deferred
{
  // MARK: onValue: execute a task when (and only when) a computation succeeds

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes determined with a value
  /// The closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter task: the closure to be enqueued

  public func onValue(qos qos: qos_class_t = QOS_CLASS_UNSPECIFIED, _ task: (T) -> Void)
  {
    notify(qos: qos) { if let value = $0.value { task(value) } }
  }

  // MARK: onError: execute a task when (and only when) a computation fails

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes determined with an error
  /// The closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter task: the closure to be enqueued

  public func onError(qos qos: qos_class_t = QOS_CLASS_UNSPECIFIED, _ task: (ErrorType) -> Void)
  {
    notify(qos: qos) { if let error = $0.error { task(error) } }
  }
}

// MARK: map: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func map<U>(qos qos: qos_class_t = QOS_CLASS_UNSPECIFIED, _ transform: (T) throws -> U) -> Deferred<U>
  {
    return Mapped<U>(qos: qos, source: self, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func map<U>(qos qos: qos_class_t = QOS_CLASS_UNSPECIFIED, _ transform: (T) -> Result<U>) -> Deferred<U>
  {
    return Mapped<U>(qos: qos, source: self, transform: transform)
  }
}

// MARK: flatMap: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func flatMap<U>(qos qos: qos_class_t = QOS_CLASS_UNSPECIFIED, _ transform: (T) -> Deferred<U>) -> Deferred<U>
  {
    return Bind<U>(qos: qos, source: self, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously if and when `self` becomes determined with an error.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func recover(qos qos: qos_class_t = QOS_CLASS_UNSPECIFIED, _ transform: (ErrorType) -> Deferred<T>) -> Deferred<T>
  {
    return Bind(qos: qos, source: self, transform: transform)
  }
}

// MARK: apply: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become determined.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func apply<U>(qos qos: qos_class_t = QOS_CLASS_UNSPECIFIED, _ transform: Deferred<(T) -> Result<U>>) -> Deferred<U>
  {
    return Applicator<U>(qos: qos, source: self, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become determined.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func apply<U>(qos qos: qos_class_t = QOS_CLASS_UNSPECIFIED, _ transform: Deferred<(T) throws -> U>) -> Deferred<U>
  {
    return Applicator<U>(qos: qos, source: self, transform: transform)
  }

  /// Adaptor made desirable by insufficient covariance from throwing to non-throwing closure types. (radar 22013315)
  /// (i.e. if the difference between the type signature of two closures is whether they throw,
  /// the non-throwing one should be usable anywhere the throwing one can.)
  /// Can hopefully be removed later.
  ///
  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become determined.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform

  public final func apply<U>(qos qos: qos_class_t = QOS_CLASS_UNSPECIFIED, _ transform: Deferred<(T) -> U>) -> Deferred<U>
  {
    let retransform = transform.map(qos: qos) { transform in { t throws in transform(t) } }
    return Applicator<U>(qos: qos, source: self, transform: retransform)
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
/// Deferred { try deferreds.map { do { try $0.result.getValue() } catch { throw error } }
/// ```
/// - parameter deferreds: an array of `Deferred`
/// - returns: a new `Deferred`

public func combine<T>(deferreds: [Deferred<T>]) -> Deferred<[T]>
{
  return deferreds.reduce(Deferred<[T]>(value: [])) {
    (accumulator, element) in
    accumulator.flatMap {
      values in
      return element.map {
        value in
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
      (_: Result<T>) in
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
    let deferreds = self.indices.map { _ in TBD<T>() }
    for (index, tbd) in zip(self.indices, deferreds)
    {
      dispatch_async(queue) {
        tbd.beginExecution()
        let result = Result { _ in try task(self[index]) }
        _ = try? tbd.determine(result) // an error here means this `TBD` has been canceled
      }
    }
    return deferreds
  }
}
