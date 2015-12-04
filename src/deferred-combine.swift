//
//  deferred-combine.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 06/11/2015.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import shuffle

// combine two or more Deferred objects into one.

/// Combine an array of `Deferred`s into a new `Deferred` whose value is an array.
/// The combined `Deferred` will become determined after every input `Deferred` is determined.
/// If any of the elements resolves to an error, the combined `Deferred` will be an error.
/// The combined `Deferred` will use the queue from the first element of the input array (unless the input array is empty.)
///
/// - parameter deferreds: an array of `Deferred`
/// - returns: a new `Deferred`

public func combine<T>(deferreds: [Deferred<T>]) -> Deferred<[T]>
{
  guard let first = deferreds.first else { return Deferred<[T]>(value: []) }

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

/// Combine two `Deferred` into one.
/// The returned `Deferred` will become determined after both inputs are determined.
/// If either of the elements resolves to an error, the combined `Deferred` will be an error.
/// The combined `Deferred` will use the queue from the first input, `d1`.
///
/// - parameter d1: a `Deferred`
/// - parameter d2: a second `Deferred` to combine with `d1`
/// - returns: a new `Deferred` whose value shall be a tuple of `d1.value` and `d2.value`

public func combine<T1,T2>(d1: Deferred<T1>, _ d2: Deferred<T2>) -> Deferred<(T1,T2)>
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

public func combine<T1,T2,T3>(d1: Deferred<T1>, _ d2: Deferred<T2>, _ d3: Deferred<T3>) -> Deferred<(T1,T2,T3)>
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

public func combine<T1,T2,T3,T4>(d1: Deferred<T1>, _ d2: Deferred<T2>, _ d3: Deferred<T3>, _ d4: Deferred<T4>) -> Deferred<(T1,T2,T3,T4)>
{
  return combine(d1,d2,d3).flatMap { (t1,t2,t3) in d4.map { t4 in (t1,t2,t3,t4) } }
}

/// Return the value of the first of an array of `Deferred`s to be determined.
/// Note that if the array is empty the resulting `Deferred` will resolve to a `NoResult` error.
///
/// - parameter deferreds: an array of `Deferred`
/// - returns: a new `Deferred`

public func firstValue<T>(deferreds: [Deferred<T>]) -> Deferred<T>
{
  if deferreds.count == 0
  {
    return Deferred(Result())
  }

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
/// Note that if the array is empty the resulting `Deferred` will resolve to a `NoResult` error.
///
/// - parameter deferreds: an array of `Deferred`
/// - returns: a new `Deferred`

public func firstDetermined<T>(deferreds: [Deferred<T>]) -> Deferred<Deferred<T>>
{
  if deferreds.count == 0
  {
    return Deferred(Result())
  }

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
