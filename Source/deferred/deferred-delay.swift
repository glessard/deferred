//
//  deferred-delay.swift
//  deferred
//
//  Created by Guillaume Lessard
//  Copyright © 2017-2020 Guillaume Lessard. All rights reserved.
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

    return Deferred(queue: queue ?? self.queue) {
      resolver in
      self.notify(queue: queue, boostQoS: false) {
        result in
        guard resolver.needsResolution else { return }

        if case .failure = result
        { // don't honor the time delay for the error case
          resolver.resolve(result)
          return
        }

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
