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
  /// Return a `Deferred` whose determination will occur at least a number of seconds from the time of evaluation.
  /// Note that a cancellation or error will result in early determination.
  ///
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - returns: a `Deferred` reference

  public func delay(queue: DispatchQueue? = nil, seconds delay: Double) -> Deferred
  {
    return self.delay(queue: queue, until: .now() + delay)
  }

  /// Return a `Deferred` whose determination will occur at the earliest`delay` from the time of evaluation.
  /// Note that a cancellation or error will result in early determination.
  ///
  /// - parameter delay: a time interval, as `DispatchTimeInterval`
  /// - returns: a `Deferred` reference

  public func delay(queue: DispatchQueue? = nil, _ delay: DispatchTimeInterval) -> Deferred
  {
    return self.delay(queue: queue, until: .now() + delay)
  }

  /// Return a `Deferred` whose determination will occur after a given timestamp.
  /// Note that a cancellation or error will result in early determination.
  ///
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - returns: a `Deferred` reference

  public func delay(queue: DispatchQueue? = nil, until time: DispatchTime) -> Deferred
  { // FIXME: don't special-case .distantFuture (https://bugs.swift.org/browse/SR-5706)
    guard time > .now() || time == .distantFuture else { return self }
    return Delayed(queue: queue, source: self, until: time)
  }
}

// MARK: maximum time until a `Deferred` becomes determined

extension Deferred
{
  /// Ensure this `Deferred` will be determined by the given deadline.
  /// If `self` has not become determined before the timeout expires, `self` will be canceled.
  ///
  /// - parameter seconds: a number of seconds as a `Double` or `NSTimeInterval`
  /// - parameter reason: the reason for the cancellation if the operation times out. Defaults to "Deferred operation timed out".
  /// - returns: self

  @discardableResult
  public func timeout(seconds: Double, reason: String = "") -> Deferred
  {
    return self.timeout(after: .now() + seconds, reason: reason)
  }

  /// Ensure this `Deferred` will be determined by the given deadline.
  /// If `self` has not become determined before the timeout expires, `self` will be canceled.
  ///
  /// - parameter timeout: a time interval
  /// - parameter reason: the reason for the cancellation if the operation times out. Defaults to "Deferred operation timed out".
  /// - returns: self

  @discardableResult
  public func timeout(_ timeout: DispatchTimeInterval, reason: String = "") -> Deferred
  {
    return self.timeout(after: .now() + timeout, reason: reason)
  }

  /// Ensure this `Deferred` will be determined by the given deadline.
  /// If `self` has not become determined before the timeout expires, `self` will be canceled.
  ///
  /// - parameter deadline: a timestamp used as a deadline
  /// - parameter reason: the reason for the cancellation if the operation times out. Defaults to "Deferred operation timed out".
  /// - returns: self

  @discardableResult
  public func timeout(after deadline: DispatchTime, reason: String = "") -> Deferred
  {
    if isDetermined { return self }

    if deadline < .now()
    {
      cancel(.timedOut(reason))
    }
    else if deadline != .distantFuture
    {
      let queue = DispatchQueue(label: "timeout", qos: qos)
      queue.asyncAfter(deadline: deadline) { self.cancel(.timedOut(reason)) }
    }
    return self
  }
}
