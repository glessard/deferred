//
//  deferred-combine.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 06/11/2015.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

// Until Xcode supports the Swift package manager, compile with the flag "-D XCODE"
#if !XCODE
  import shuffle
#endif

// combine two or more Deferred objects into one.

/// Combine an array of `Deferred`s into a new `Deferred` whose value is an array.
/// The combined `Deferred` will become determined after every input `Deferred` is determined.
/// If any of the elements resolves to an error, the combined `Deferred` will be an error.
/// The combined `Deferred` will use the queue from the first element of the input array (unless the input array is empty.)
///
/// - parameter deferreds: an array of `Deferred`
/// - returns: a new `Deferred`

public func combine<Value>(_ deferreds: [Deferred<Value>]) -> Deferred<[Value]>
{
  guard let first = deferreds.first else { return Deferred<[Value]>(value: []) }

  let accumulator = first.map { value in [value] }

  return deferreds[1..<deferreds.endIndex].reduce(accumulator) {
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

/// Combine a Sequence of `Deferred`s into a new `Deferred` whose value is an array.
/// The combined `Deferred` will become determined after every input `Deferred` is determined.
/// If any of the elements resolves to an error, the combined `Deferred` will be an error.
/// The combined `Deferred` will use the queue from the first element of the input array (unless the input array is empty.)
///
/// - parameter deferreds: an array of `Deferred`
/// - returns: a new `Deferred`

public func combine<Value, S: Sequence where
                    S.Iterator.Element == Deferred<Value>>(_ deferreds: S) -> Deferred<[Value]>
{
  // We should combine on a background thread because S could block on next()

  let combiner = Deferred<Deferred<[Value]>> {
    deferreds.reduce(Deferred<[Value]>(value: [])) {
      (accumulator, element) in
      accumulator.flatMap {
        values in
        element.map {
          value in
          values + [value]
        }
      }
    }
  }

  return combiner.flatMap { $0 }
}

/// Combine two `Deferred` into one.
/// The returned `Deferred` will become determined after both inputs are determined.
/// If either of the elements resolves to an error, the combined `Deferred` will be an error.
/// The combined `Deferred` will use the queue from the first input, `d1`.
///
/// - parameter d1: a `Deferred`
/// - parameter d2: a second `Deferred` to combine with `d1`
/// - returns: a new `Deferred` whose value shall be a tuple of `d1.value` and `d2.value`

public func combine<T1,T2>(_ d1: Deferred<T1>, _ d2: Deferred<T2>) -> Deferred<(T1,T2)>
{
  return d1.flatMap { t1 in d2.map { t2 in (t1,t2) } }
}

/// Combine three `Deferred` into one.
/// The returned `Deferred` will become determined after all inputs are determined.
/// If any of the elements resolves to an error, the combined `Deferred` will be an error.
/// The combined `Deferred` will use the queue from the first input, `d1`.
///
/// - parameter d1: a `Deferred`
/// - parameter d2: a second `Deferred` to combine
/// - parameter d3: a third `Deferred` to combine
/// - returns: a new `Deferred` whose value shall be a tuple of the inputs's values

public func combine<T1,T2,T3>(_ d1: Deferred<T1>, _ d2: Deferred<T2>, _ d3: Deferred<T3>) -> Deferred<(T1,T2,T3)>
{
  return combine(d1,d2).flatMap { (t1,t2) in d3.map { t3 in (t1,t2,t3) } }
}

/// Combine four `Deferred` into one.
/// The returned `Deferred` will become determined after all inputs are determined.
/// If any of the elements resolves to an error, the combined `Deferred` will be an error.
/// The combined `Deferred` will use the queue from the first input, `d1`.
///
/// - parameter d1: a `Deferred`
/// - parameter d2: a second `Deferred` to combine
/// - parameter d3: a third `Deferred` to combine
/// - parameter d4: a fourth `Deferred` to combine
/// - returns: a new `Deferred` whose value shall be a tuple of the inputs's values

public func combine<T1,T2,T3,T4>(_ d1: Deferred<T1>, _ d2: Deferred<T2>, _ d3: Deferred<T3>, _ d4: Deferred<T4>) -> Deferred<(T1,T2,T3,T4)>
{
  return combine(d1,d2,d3).flatMap { (t1,t2,t3) in d4.map { t4 in (t1,t2,t3,t4) } }
}

/// Return the value of the first of an array of `Deferred`s to be determined.
/// Note that if the array is empty the resulting `Deferred` will resolve to a `NoResult` error.
///
/// - parameter deferreds: an array of `Deferred`
/// - returns: a new `Deferred`

public func firstValue<Value>(_ deferreds: [Deferred<Value>]) -> Deferred<Value>
{
  if deferreds.count == 0
  {
    return Deferred(Result())
  }

  return firstDetermined(ShuffledSequence(deferreds)).flatMap { $0 }
}

public func firstValue<Value, S: Sequence where
                       S.Iterator.Element == Deferred<Value>>(_ deferreds: S) -> Deferred<Value>
{
  return firstDetermined(deferreds).flatMap { $0 }
}

/// Return the first of an array of `Deferred`s to become determined.
/// Note that if the array is empty the resulting `Deferred` will resolve to a `NoResult` error.
///
/// - parameter deferreds: an array of `Deferred`
/// - returns: a new `Deferred`

public func firstDetermined<Value>(_ deferreds: [Deferred<Value>]) -> Deferred<Deferred<Value>>
{
  if deferreds.count == 0
  {
    return Deferred(Result())
  }

  return firstDetermined(ShuffledSequence(deferreds))
}

import Dispatch

public func firstDetermined<Value, S: Sequence where
                            S.Iterator.Element == Deferred<Value>>(_ deferreds: S) -> Deferred<Deferred<Value>>
{
  let first = TBD<Deferred<Value>>()

  // We iterate on a background thread because S could block on next()
  dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
    deferreds.forEach {
      deferred in
      deferred.notify {
        _ in
        // an error here just means `deferred` wasn't the first to become determined
        _ = try? first.determine(deferred)
      }
    }
  }
  return first
}
