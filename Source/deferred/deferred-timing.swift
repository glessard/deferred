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

  public final func delay(seconds delay: Double) -> Deferred
  {
    return self.delay(until: .now() + delay)
  }

  /// Return a `Deferred` whose determination will occur at the earliest`delay` from the time of evaluation.
  /// Note that a cancellation or error will result in early determination.
  ///
  /// - parameter delay: a time interval, as `DispatchTimeInterval`
  /// - returns: a `Deferred` reference

  public final func delay(_ delay: DispatchTimeInterval) -> Deferred
  {
    return self.delay(until: .now() + delay)
  }

  /// Return a `Deferred` whose determination will occur after a given timestamp.
  /// Note that a cancellation or error will result in early determination.
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
