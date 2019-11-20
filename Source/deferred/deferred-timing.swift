//
//  deferred-timing.swift
//  deferred
//
//  Created by Guillaume Lessard on 8/29/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import Dispatch

/*
 Definitions that rely on or extend Deferred, but do not need the fundamental, private stuff.
*/

// MARK: minimum delay until a `Deferred` has a value

extension Deferred
{
  /// Return a `Deferred` whose resolution will occur at least a number of seconds from the time of evaluation.
  ///
  /// Note that a cancellation or error will result in early resolution.
  ///
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - returns: a `Deferred` reference

  public func delay(queue: DispatchQueue? = nil, seconds delay: Double) -> Deferred
  {
    return self.delay(queue: queue, until: .now() + delay)
  }

  /// Return a `Deferred` whose resolution will occur at the earliest`delay` from the time of evaluation.
  ///
  /// Note that a cancellation or error will result in early resolution.
  ///
  /// - parameter delay: a time interval, as `DispatchTimeInterval`
  /// - returns: a `Deferred` reference

  public func delay(queue: DispatchQueue? = nil, _ delay: DispatchTimeInterval) -> Deferred
  {
    return self.delay(queue: queue, until: .now() + delay)
  }

  /// Return a `Deferred` whose resolution will occur after a given timestamp.
  ///
  /// Note that a cancellation or error will result in early resolution.
  ///
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - returns: a `Deferred` reference

  public func delay(queue: DispatchQueue? = nil, until time: DispatchTime) -> Deferred
  {
    guard time > .now() else { return self }

    return TBD(queue: queue ?? self.queue) {
      resolver in
      self.notify(queue: queue, boostQoS: false) {
        result in
        guard resolver.needsResolution else { return }

        if result.isError
        { // don't honor the time delay for the error case
          resolver.resolve(result)
          return
        }

        resolver.beginExecution()
        if time == .distantFuture { return }
        // enqueue block only if it can get executed
        if time > .now()
        {
          (queue ?? self.queue).asyncAfter(deadline: time) {
            resolver.resolve(result)
          }
        }
        else
        {
          resolver.resolve(result)
        }
      }
      resolver.retainSource(self)
    }
  }
}

// MARK: maximum time until a `Deferred` becomes resolved

extension Deferred
{
  /// Ensure this `Deferred` will be resolved by the given deadline.
  ///
  /// If `self` has not become resolved before the timeout expires, `self` will be canceled.
  ///
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - parameter reason: the reason for the cancellation if the operation times out. Defaults to "Deferred operation timed out".
  /// - returns: self

  @discardableResult
  public func timeout(seconds: Double, reason: String = "") -> Deferred<Success, Error>
  {
    return self.timeout(after: .now() + seconds, reason: reason)
  }

  /// Ensure this `Deferred` will be resolved by the given deadline.
  ///
  /// If `self` has not become resolved before the timeout expires, `self` will be canceled.
  ///
  /// - parameter timeout: a time interval
  /// - parameter reason: the reason for the cancellation if the operation times out. Defaults to "Deferred operation timed out".
  /// - returns: self

  @discardableResult
  public func timeout(_ timeout: DispatchTimeInterval, reason: String = "") -> Deferred<Success, Error>
  {
    return self.timeout(after: .now() + timeout, reason: reason)
  }

  /// Ensure this `Deferred` will be resolved by the given deadline.
  ///
  /// If `self` has not become resolved before the timeout expires, `self` will be canceled.
  ///
  /// - parameter deadline: a timestamp used as a deadline
  /// - parameter reason: the reason for the cancellation if the operation times out. Defaults to "Deferred operation timed out".
  /// - returns: self

  @discardableResult
  public func timeout(after deadline: DispatchTime, reason: String = "") -> Deferred<Success, Error>
  {
    if self.isResolved { return self.withAnyError }

    let withTimeout: Deferred<Success, Error>
    if let t = self as? Deferred<Success, Error>
    { withTimeout = t }
    else
    { withTimeout = self.withAnyError }

    if deadline < .now()
    {
      withTimeout.cancel(.timedOut(reason))
      return withTimeout
    }
    else if deadline != .distantFuture
    {
      let queue = DispatchQueue(label: "timeout", qos: qos)
      queue.asyncAfter(deadline: deadline) { [weak withTimeout] in withTimeout?.cancel(.timedOut(reason)) }
    }
    return withTimeout
  }
}

extension Deferred where Failure == Cancellation
{
  /// Ensure this `Deferred` will be resolved by the given deadline.
  ///
  /// If `self` has not become resolved before the timeout expires, `self` will be canceled.
  ///
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - parameter reason: the reason for the cancellation if the operation times out. Defaults to "Deferred operation timed out".
  /// - returns: self

  @discardableResult
  public func timeout(seconds: Double, reason: String = "") -> Deferred<Success, Cancellation>
  {
    return self.timeout(after: .now() + seconds, reason: reason)
  }

  /// Ensure this `Deferred` will be resolved by the given deadline.
  ///
  /// If `self` has not become resolved before the timeout expires, `self` will be canceled.
  ///
  /// - parameter timeout: a time interval
  /// - parameter reason: the reason for the cancellation if the operation times out. Defaults to "Deferred operation timed out".
  /// - returns: self

  @discardableResult
  public func timeout(_ timeout: DispatchTimeInterval, reason: String = "") -> Deferred<Success, Cancellation>
  {
    return self.timeout(after: .now() + timeout, reason: reason)
  }

  /// Ensure this `Deferred` will be resolved by the given deadline.
  ///
  /// If `self` has not become resolved before the timeout expires, `self` will be canceled.
  ///
  /// - parameter deadline: a timestamp used as a deadline
  /// - parameter reason: the reason for the cancellation if the operation times out. Defaults to "Deferred operation timed out".
  /// - returns: self

  @discardableResult
  public func timeout(after deadline: DispatchTime, reason: String = "") -> Deferred<Success, Cancellation>
  {
    if self.isResolved { return self }

    if deadline < .now()
    {
      cancel(.timedOut(reason))
    }
    else if deadline != .distantFuture
    {
      let queue = DispatchQueue(label: "timeout", qos: qos)
      queue.asyncAfter(deadline: deadline) { [weak self] in self?.cancel(.timedOut(reason)) }
    }
    return self
  }
}

extension Deferred where Failure == Never
{
  /// Ensure this `Deferred` will be resolved by the given deadline.
  ///
  /// If `self` has not become resolved before the timeout expires, `self` will be canceled.
  ///
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - parameter reason: the reason for the cancellation if the operation times out. Defaults to "Deferred operation timed out".
  /// - returns: self

  @discardableResult
  public func timeout(seconds: Double, reason: String = "") -> Deferred<Success, Cancellation>
  {
    return self.timeout(after: .now() + seconds, reason: reason)
  }

  /// Ensure this `Deferred` will be resolved by the given deadline.
  ///
  /// If `self` has not become resolved before the timeout expires, `self` will be canceled.
  ///
  /// - parameter timeout: a time interval
  /// - parameter reason: the reason for the cancellation if the operation times out. Defaults to "Deferred operation timed out".
  /// - returns: self

  @discardableResult
  public func timeout(_ timeout: DispatchTimeInterval, reason: String = "") -> Deferred<Success, Cancellation>
  {
    return self.timeout(after: .now() + timeout, reason: reason)
  }

  /// Ensure this `Deferred` will be resolved by the given deadline.
  ///
  /// If `self` has not become resolved before the timeout expires, `self` will be canceled.
  ///
  /// - parameter deadline: a timestamp used as a deadline
  /// - parameter reason: the reason for the cancellation if the operation times out. Defaults to "Deferred operation timed out".
  /// - returns: self

  @discardableResult
  public func timeout(after deadline: DispatchTime, reason: String = "") -> Deferred<Success, Cancellation>
  {
    return self.mapError(transform: { _ in Cancellation.timedOut("") }).timeout(after: deadline, reason: reason)
  }
}
