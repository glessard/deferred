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
  /// Return a `Deferred` whose determination will occur at least a number of seconds from the time of evaluation.
  /// Note that a cancelation or error will result in early determination.
  ///
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - returns: a `Deferred` reference

  public final func delay(seconds delay: Double) -> Deferred
  {
    return self.delay(until: .now() + delay)
  }

  /// Return a `Deferred` whose determination will occur at the earliest`delay` from the time of evaluation.
  /// Note that a cancelation or error will result in early determination.
  ///
  /// - parameter delay: a time interval, as `DispatchTimeInterval`
  /// - returns: a `Deferred` reference

  public final func delay(_ delay: DispatchTimeInterval) -> Deferred
  {
    return self.delay(until: .now() + delay)
  }

  /// Return a `Deferred` whose determination will occur after a given timestamp.
  /// Note that a cancelation or error will result in early determination.
  ///
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - returns: a `Deferred` reference

  public final func delay(until time: DispatchTime) -> Deferred
  { // FIXME: don't special-case .distantFuture (https://bugs.swift.org/browse/SR-5706)
    guard time > .now() || time == .distantFuture else { return self }

    return Delayed(source: self, until: time)
  }
}

// MARK: maximum time until a `Deferred` becomes determined

@_versioned let DefaultTimeoutMessage = "Operation timed out"

extension Deferred
{
  /// Ensure this `Deferred` will be determined by the given deadline.
  /// If `self` has not become determined before the timeout expires, `self` will be canceled.
  ///
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - parameter reason: the reason for the cancelation if the operation times out. Defaults to "Operation timed out".
  /// - returns: self

  @discardableResult
  public final func timeout(seconds: Double, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    return self.timeout(after: .now() + seconds, reason: reason)
  }

  /// Ensure this `Deferred` will be determined by the given deadline.
  /// If `self` has not become determined before the timeout expires, `self` will be canceled.
  ///
  /// - parameter timeout: a time interval
  /// - parameter reason: the reason for the cancelation if the operation times out. Defaults to "Operation timed out".
  /// - returns: self

  @discardableResult
  public final func timeout(_ timeout: DispatchTimeInterval, reason: String = DefaultTimeoutMessage) -> Deferred
  {
    return self.timeout(after: .now() + timeout, reason: reason)
  }

  /// Ensure this `Deferred` will be determined by the given deadline.
  /// If `self` has not become determined before the timeout expires, `self` will be canceled.
  ///
  /// - parameter deadline: a timestamp used as a deadline
  /// - parameter reason: the reason for the cancelation if the operation times out. Defaults to "Operation timed out".
  /// - returns: self

  @discardableResult
  public final func timeout(after deadline: DispatchTime, reason: String = DefaultTimeoutMessage) -> Deferred
  { // FIXME: don't special-case .distantFuture (https://bugs.swift.org/browse/SR-5706)
    if deadline == .distantFuture || isDetermined
    {
      return self
    }

    guard deadline > .now() else
    {
      self.cancel(reason)
      return self
    }

    let queue = DispatchQueue.global(qos: self.qos.qosClass)
    queue.asyncAfter(deadline: deadline) { self.cancel(reason) }
    return self
  }
}

extension Deferred
{
  // MARK: onValue: execute a task when (and only when) a computation succeeds

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes determined with a value
  /// The closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter task: the closure to be enqueued

  public func onValue(qos: DispatchQoS? = nil, task: @escaping (Value) -> Void)
  {
    notify(qos: qos) { if case let .value(v) = $0 { task(v) } }
  }

  // MARK: onError: execute a task when (and only when) a computation fails

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes determined with an error
  /// The closure will be enqueued on the global queue with the requested quality of service.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter task: the closure to be enqueued

  public func onError(qos: DispatchQoS? = nil, task: @escaping (Error) -> Void)
  {
    notify(qos: qos) { if case let .error(e) = $0 { task(e) } }
  }
}

// MARK: map: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func map<Other>(qos: DispatchQoS? = nil, transform: @escaping (Value) throws -> Other) -> Deferred<Other>
  {
    return Mapped<Other>(qos: qos, source: self, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes determined.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the queue's QOS class.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func map<Other>(qos: DispatchQoS? = nil, transform: @escaping (Value) -> Result<Other>) -> Deferred<Other>
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

  public func flatMap<Other>(qos: DispatchQoS? = nil, transform: @escaping (Value) -> Deferred<Other>) -> Deferred<Other>
  {
    return Bind<Other>(qos: qos, source: self, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously if and when `self` becomes determined with an error.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func recover(qos: DispatchQoS? = nil, transform: @escaping (Error) -> Deferred<Value>) -> Deferred<Value>
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

  public func apply<Other>(qos: DispatchQoS? = nil, transform: Deferred<(Value) -> Result<Other>>) -> Deferred<Other>
  {
    return Applicator<Other>(qos: qos, source: self, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become determined.
  /// - parameter qos: the QOS class at which to execute the transform; defaults to the QOS class of this Deferred's queue.
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform

  public func apply<Other>(qos: DispatchQoS? = nil, transform: Deferred<(Value) throws -> Other>) -> Deferred<Other>
  {
    return Applicator<Other>(qos: qos, source: self, transform: transform)
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

  public final func apply<Other>(qos: DispatchQoS? = nil, transform: Deferred<(Value) -> Other>) -> Deferred<Other>
  {
    let retransform = transform.map(qos: qos) { transform in { v throws in transform(v) } }
    return Applicator<Other>(qos: qos, source: self, transform: retransform)
  }
}

extension Deferred
{
  /// Insert a validation step in a chain of Deferred.
  /// Pass `Value` if it passes the predicate, otherwise replace it with the error `DeferredError.invalid`.
  ///
  /// - parameter qos: the QOS class at which to execute the predicate; defaults to the QOS class of this Deferred's queue.
  /// - parameter predicate: a predicate that validates the passed-in `Value`.
  /// - returns: a `Deferred` reference holding a validated `Value`

  public final func validate(qos: DispatchQoS? = nil, predicate: @escaping (Value) -> Bool, message: String = "") -> Deferred<Value>
  {
    return self.map(qos: qos) {
      value in
      guard predicate(value)
      else { throw DeferredError.invalid(message) }
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
    let result = Result(self, or: DeferredError.invalid("Deferred initialized from a nil Optional"))
    return Deferred(result)
  }

  /// Create a `Deferred` from this `Optional`.
  /// If `optional` is `nil` then `Deferred` will be determined with the error `DeferredError.invalid`
  ///
  /// - parameter qos: the Quality-of-Service class at which to perform notifications for the new `Deferred`

  public func deferred(qos: DispatchQoS = DispatchQoS.current ?? .default) -> Deferred<Wrapped>
  {
    let queue = DispatchQueue.global(qos: qos.qosClass)
    return self.deferred(queue: queue)
  }
}
