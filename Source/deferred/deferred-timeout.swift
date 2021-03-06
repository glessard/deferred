//
//  deferred-timeout.swift
//  deferred
//
//  Created by Guillaume Lessard
//  Copyright © 2017-2020 Guillaume Lessard. All rights reserved.
//

import Dispatch

/*
 Definitions that rely on or extend Deferred, but do not need the fundamental, private stuff.
*/

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

  public func timeout(after deadline: DispatchTime, reason: String = "") -> Deferred<Success, Error>
  {
    if self.isResolved { return self.withAnyError }

    let broadened: Deferred<Success, Error>
    if let t = self as? Deferred<Success, Error>
    { broadened = t }
    else
    { broadened = self.withAnyError }

    let timedOut = Cancellation.timedOut(reason)
    if let timedOut = convertCancellation(timedOut)
    {
      if deadline < .now()
      {
        self.cancel(timedOut)
      }
      else if deadline != .distantFuture
      {
        let queue = DispatchQueue.global(qos: qos.qosClass)
        queue.asyncAfter(deadline: deadline) { [weak self] in self?.cancel(timedOut) }
      }
      return broadened
    }

    if deadline < .now()
    {
      broadened.cancel(timedOut)
    }
    else if deadline != .distantFuture
    {
      let queue = DispatchQueue.global(qos: qos.qosClass)
      queue.asyncAfter(deadline: deadline) { [weak broadened] in broadened?.cancel(timedOut) }
    }
    return broadened
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

    let timedOut = Cancellation.timedOut(reason)
    if deadline < .now()
    {
      cancel(timedOut)
    }
    else if deadline != .distantFuture
    {
      let queue = DispatchQueue.global(qos: qos.qosClass)
      queue.asyncAfter(deadline: deadline) { [weak self] in self?.cancel(timedOut) }
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

  public func timeout(after deadline: DispatchTime, reason: String = "") -> Deferred<Success, Cancellation>
  {
    return self.setFailureType(to: Cancellation.self).timeout(after: deadline, reason: reason)
  }
}
