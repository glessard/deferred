//
//  deferred-combine.swift
//  deferred
//
//  Created by Guillaume Lessard on 06/11/2015.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

// combine two or more Deferred objects into one.

/// Combine a Sequence of `Deferred`s into a new `Deferred` whose value is an array.
///
/// The combined `Deferred` will become resolved after every input `Deferred` has become resolved.
///
/// The combined `Deferred` will use a new queue at the requested (or current) QoS.
///
/// If any of the elements resolves to an error, the combined `Deferred` will contain that error.
///
/// - parameter qos: the QoS at which the `combine` operation and its notifications should occur; defaults to the current QoS class
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - returns: a new `Deferred`

public func combine<Success, Failure, S>(qos: DispatchQoS = .current,
                                         deferreds: S) -> Deferred<[Success], Failure>
  where Failure: Error, S: Sequence, S.Element == Deferred<Success, Failure>
{
  let queue = DispatchQueue(label: "reduce-sequence", qos: qos)
  return combine(queue: queue, deferreds: deferreds)
}

/// Combine a Sequence of `Deferred`s into a new `Deferred` whose value is an array.
///
/// The combined `Deferred` will become resolved after every input `Deferred` is resolved.
///
/// The combined `Deferred` will use a new queue at the current QoS.
///
/// If any of the elements resolves to an error, the combined `Deferred` will contain that error.
///
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - returns: a new `Deferred`

public func combine<Success, Failure, S>(_ deferreds: S) -> Deferred<[Success], Failure>
  where Failure: Error, S: Sequence, S.Element == Deferred<Success, Failure>
{
  return combine(qos: .current, deferreds: deferreds)
}

/// Combine a Sequence of `Deferred`s into a new `Deferred` whose value is an array.
///
/// The combined `Deferred` will become resolved after every input `Deferred` is resolved.
///
/// The combined `Deferred` will use the supplied queue.
///
/// If any of the elements resolves to an error, the combined `Deferred` will contain that error.
///
/// - parameter queue: the queue onto which the `combine` operation and its notifications will occur
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - returns: a new `Deferred`

public func combine<Success, Failure, S>(queue: DispatchQueue, deferreds: S) -> Deferred<[Success], Failure>
  where Failure: Error, S: Sequence, S.Element == Deferred<Success, Failure>
{
  var combined = [Success]()

  let reduced = reduce(queue: queue, deferreds: deferreds, initial: ()) {
    _, value in combined.append(value)
  }
  return reduced.map(transform: { _ in combined })
}

/// Returns the result of repeatedly calling `combine` with an
/// accumulated value initialized to `initial` and each element of
/// `deferreds`, in turn.
///
/// That is, return a deferred version of
/// `combine(combine(...combine(combine(initial, deferreds[0].value),
/// deferreds[1].value),...deferreds[count-2].value), deferreds[count-1].value)`.
/// (Never mind that you can't index a Sequence.)
///
/// If any of the elements resolves to an error, the resulting `Deferred` will contain that error.
///
/// If the reducing function throws an error, the resulting `Deferred` will contain that error.
///
/// The combined `Deferred` will use a new queue at the requested QoS.
///
/// - parameter qos: the QoS at which the `reduce` operation and its notifications should occur; defaults to the current QoS class
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter initial: a value to use as the initial accumulating value
/// - parameter combine: a reducing function
/// - returns: a new `Deferred`
/// - parameter accumulated: the accumulated value up to this element of the `Collection`
/// - parameter element: a new element to be accumulated

public func reduce<S, T, F, U>(qos: DispatchQoS,
                               deferreds: S, initial: U,
                               combine: @escaping (_ accumulated: U, _ element: T) -> U) -> Deferred<U, F>
  where S: Sequence, S.Element == Deferred<T, F>
{
  let queue = DispatchQueue(label: "reduce-sequence", qos: qos)
  return reduce(queue: queue, deferreds: deferreds, initial: initial, combine: combine)
}

/// Returns the result of repeatedly calling `combine` with an
/// accumulated value initialized to `initial` and each element of
/// `deferreds`, in turn.
///
/// That is, return a deferred version of
/// `combine(combine(...combine(combine(initial, deferreds[0].value),
/// deferreds[1].value),...deferreds[count-2].value), deferreds[count-1].value)`.
/// (Never mind that you can't index a Sequence.)
///
/// If any of the elements resolves to an error, the resulting `Deferred` will contain that error.
///
/// If the reducing function throws an error, the resulting `Deferred` will contain that error.
///
/// The combined `Deferred` will use a new queue at the current QoS.
///
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter initial: a value to use as the initial accumulating value
/// - parameter combine: a reducing function
/// - returns: a new `Deferred`
/// - parameter accumulated: the accumulated value up to this element of the `Collection`
/// - parameter element: a new element to be accumulated

public func reduce<S, T, F, U>(_ deferreds: S, initial: U,
                               combine: @escaping (_ accumulated: U, _ element: T) -> U) -> Deferred<U, F>
  where S: Sequence, S.Element == Deferred<T, F>
{
  return reduce(qos: .current, deferreds: deferreds, initial: initial, combine: combine)
}

/// Returns the result of repeatedly calling `combine` with an
/// accumulated value initialized to `initial` and each element of
/// `deferreds`, in turn.
///
/// That is, return a deferred version of
/// `combine(combine(...combine(combine(initial, deferreds[0].value),
/// deferreds[1].value),...deferreds[count-2].value), deferreds[count-1].value)`.
/// (Never mind that you can't index a Sequence.)
///
/// If any of the elements resolves to an error, the resulting `Deferred` will contain that error.
///
/// If the reducing function throws an error, the resulting `Deferred` will contain that error.
///
/// The combined `Deferred` will use the supplied queue.
///
/// - parameter queue: the queue onto which the `reduce` operation and its notifications will occur
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter initial: a value to use as the initial accumulating value
/// - parameter combine: a reducing function
/// - returns: a new `Deferred`
/// - parameter accumulated: the accumulated value up to this element of the `Collection`
/// - parameter element: a new element to be accumulated

public func reduce<S, T, F, U>(queue: DispatchQueue,
                               deferreds: S, initial: U,
                               combine: @escaping (_ accumulated: U, _ element: T) -> U) -> Deferred<U, F>
  where S: Sequence, S.Element == Deferred<T, F>
{
  // We execute `Sequence.reduce` asynchronously because
  // nothing prevents S from blocking on `Sequence.next()`
  let reduced = Deferred<Deferred<U, F>, Never>(queue: queue) {
    resolver in
    let r = deferreds.reduce(Deferred<U, F>(queue: .global(qos: queue.qos.qosClass), value: initial)) {
      (accumulator, deferred) in
      accumulator.flatMap {
        u in deferred.map(queue: queue) { t in combine(u,t) }
      }
    }
    resolver.resolve(value: r)
  }

  return reduced.flatten()
}

/// Combine two `Deferred` into one.
///
/// The returned `Deferred` will become resolved after both inputs are resolved.
///
/// If either of the elements resolves to an error, the combined `Deferred` will be an error.
///
/// The combined `Deferred` will use the queue from the first input, `d1`.
///
/// - parameter d1: a `Deferred`
/// - parameter d2: a second `Deferred` to combine with `d1`
/// - returns: a new `Deferred` whose value shall be a tuple of `d1.value` and `d2.value`

public func combine<T1, T2, F>(_ d1: Deferred<T1, F>,
                               _ d2: Deferred<T2, F>) -> Deferred<(T1, T2), F>
{
  return d1.flatMap { t1 in d2.map { t2 in (t1,t2) } }
}

public func combine<T1, F1, T2, F2>(_ d1: Deferred<T1, F1>,
                                    _ d2: Deferred<T2, F2>) -> Deferred<(T1, T2), Error>
{
  return combine(d1.withAnyError, d2.withAnyError)
}

/// Combine three `Deferred` into one.
///
/// The returned `Deferred` will become resolved after all inputs are resolved.
///
/// If any of the elements resolves to an error, the combined `Deferred` will be an error.
///
/// The combined `Deferred` will use the queue from the first input, `d1`.
///
/// - parameter d1: a `Deferred`
/// - parameter d2: a second `Deferred` to combine
/// - parameter d3: a third `Deferred` to combine
/// - returns: a new `Deferred` whose value shall be a tuple of the inputs's values

public func combine<T1, T2, T3, F>(_ d1: Deferred<T1, F>,
                                   _ d2: Deferred<T2, F>,
                                   _ d3: Deferred<T3, F>) -> Deferred<(T1, T2, T3), F>
{
  return combine(d1,d2).flatMap { (t1,t2) in d3.map { t3 in (t1,t2,t3) } }
}

public func combine<T1, F1, T2, F2, T3, F3>(_ d1: Deferred<T1, F1>,
                                            _ d2: Deferred<T2, F2>,
                                            _ d3: Deferred<T3, F3>) -> Deferred<(T1, T2, T3), Error>
{
  return combine(d1.withAnyError, d2.withAnyError, d3.withAnyError)
}

/// Combine four `Deferred` into one.
///
/// The returned `Deferred` will become resolved after all inputs are resolved.
///
/// If any of the elements resolves to an error, the combined `Deferred` will be an error.
///
/// The combined `Deferred` will use the queue from the first input, `d1`.
///
/// - parameter d1: a `Deferred`
/// - parameter d2: a second `Deferred` to combine
/// - parameter d3: a third `Deferred` to combine
/// - parameter d4: a fourth `Deferred` to combine
/// - returns: a new `Deferred` whose value shall be a tuple of the inputs's values

public func combine<T1, T2, T3, T4, F>(_ d1: Deferred<T1, F>,
                                       _ d2: Deferred<T2, F>,
                                       _ d3: Deferred<T3, F>,
                                       _ d4: Deferred<T4, F>) -> Deferred<(T1, T2, T3, T4), F>
{
  return combine(d1,d2,d3).flatMap { (t1,t2,t3) in d4.map { t4 in (t1,t2,t3,t4) } }
}

public func combine<T1, F1, T2, F2, T3, F3, T4, F4>(_ d1: Deferred<T1, F1>,
                                                    _ d2: Deferred<T2, F2>,
                                                    _ d3: Deferred<T3, F3>, _ d4: Deferred<T4, F4>) -> Deferred<(T1, T2, T3, T4), Error>
{
  return combine(d1.withAnyError, d2.withAnyError, d3.withAnyError, d4.withAnyError)
}
