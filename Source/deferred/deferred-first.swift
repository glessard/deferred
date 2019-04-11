//
//  deferred-first.swift
//  deferred
//
//  Created by Guillaume Lessard on 10/9/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import Dispatch

/// Return the value of the first of an array of `Deferred`s to be determined succesfully.
///
/// The returned `Deferred` be determined with an `Error` only if every input `Deferred`
/// is determined with an `Error`; in such a situation the returned `Error` will be
/// the last one to have been determined.
///
/// Note that if the `Collection` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element has a value at the time
/// the function is called, the earliest one encountered will be considered first; if this
/// biasing is a problem, consider shuffling the collection first.
///
/// - parameter qos: the QoS at which the new `Deferred`'s notifications will be executed
/// - parameter deferreds: a `Collection` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Value, C: Collection>(qos: DispatchQoS,
                                             deferreds: C, cancelOthers: Bool = false) -> Deferred<Value>
  where C.Iterator.Element: Deferred<Value>
{
  let queue = DispatchQueue(label: "first-collection", qos: qos)
  return firstValue(queue: queue, deferreds: deferreds, cancelOthers: cancelOthers)
}

/// Return the value of the first of an array of `Deferred`s to be determined succesfully.
///
/// The returned `Deferred` be determined with an `Error` only if every input `Deferred`
/// is determined with an `Error`; in such a situation the returned `Error` will be
/// the last one to have been determined.
///
/// Note that if the `Collection` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element has a value at the time
/// the function is called, the earliest one encountered will be considered first; if this
/// biasing is a problem, consider shuffling the collection first.
///
/// - parameter deferreds: a `Collection` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`, using a queue at the current QoS class.

public func firstValue<Value, C: Collection>(_ deferreds: C, cancelOthers: Bool = false) -> Deferred<Value>
  where C.Iterator.Element: Deferred<Value>
{
  return firstValue(qos: .current, deferreds: deferreds, cancelOthers: cancelOthers)
}

/// Return the value of the first of an array of `Deferred`s to be determined succesfully.
///
/// The returned `Deferred` be determined with an `Error` only if every input `Deferred`
/// is determined with an `Error`; in such a situation the returned `Error` will be
/// the error returned by the last `Deferred` in the input `Sequence`.
///
/// Note that if the `Collection` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element has a value at the time
/// the function is called, the earliest one encountered will be considered first; if this
/// biasing is a problem, consider shuffling the collection first.
///
/// - parameter queue: the `DispatchQueue` on which the new `Deferred`'s notifications will be executed.
/// - parameter deferreds: a `Collection` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Value, C: Collection>(queue: DispatchQueue,
                                             deferreds: C, cancelOthers: Bool = false) -> Deferred<Value>
  where C.Iterator.Element: Deferred<Value>
{
  if deferreds.isEmpty
  {
    let error = DeferredError.invalid("cannot find first determined value from an empty set in \(#function)")
    return Deferred(queue: queue, error: error)
  }

  let first = TBD<Value>(queue: queue) {
    f in
    var errors: [Deferred<Error>] = []
    errors.reserveCapacity(deferreds.count)

    deferreds.forEach {
      deferred in
      let e = TBD<Error>() {
        e in
        deferred.notify {
          outcome in
          do {
            let value = try outcome.get()
            f.determine(value: value)
            e.cancel()
          }
          catch {
            e.determine(value: error)
          }
        }
        if cancelOthers { f.notify { _ in deferred.cancel() }}
      }
      errors.append(e)
    }

    let combined = combine(queue: queue, deferreds: errors)
    combined.onValue { f.determine(error: $0.last!) }
    f.notify { _ in combined.cancel() }
  }

  return first
}

/// Return the value of the `Deferred`s to be determined successfully out of a `Sequence`.
///
/// The returned `Deferred` be determined with an `Error` only if every input `Deferred`
/// is determined with an `Error`; in such a situation the returned `Error` will be
/// the error returned by the last `Deferred` in the input `Sequence`.
///
/// Note that if the `Sequence` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element is already determined at the time
/// the function is called, the earliest one encountered will be considered first.
///
/// - parameter qos: the QoS at which the new `Deferred`'s notifications will be executed
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Value, S: Sequence>(qos: DispatchQoS,
                                           deferreds: S, cancelOthers: Bool = false) -> Deferred<Value>
  where S.Iterator.Element: Deferred<Value>
{
  let queue = DispatchQueue(label: "first-sequence", qos: qos)
  return firstValue(queue: queue, deferreds: deferreds, cancelOthers: cancelOthers)
}

/// Return the value of the `Deferred`s to be determined successfully out of a `Sequence`.
///
/// The returned `Deferred` be determined with an `Error` only if every input `Deferred`
/// is determined with an `Error`; in such a situation the returned `Error` will be
/// the last one to have been determined.
///
/// Note that if the `Sequence` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element is already determined at the time
/// the function is called, the earliest one encountered will be considered first.
///
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`, using a queue at the current QoS class.

public func firstValue<Value, S: Sequence>(_ deferreds: S, cancelOthers: Bool = false) -> Deferred<Value>
  where S.Iterator.Element: Deferred<Value>
{
  return firstValue(qos: .current, deferreds: deferreds, cancelOthers: cancelOthers)
}

/// Return the value of the `Deferred`s to be determined successfully out of a `Sequence`.
///
/// The returned `Deferred` be determined with an `Error` only if every input `Deferred`
/// is determined with an `Error`; in such a situation the returned `Error` will be
/// the error returned by the last `Deferred` in the input `Sequence`.
///
/// Note that if the `Sequence` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element is already determined at the time
/// the function is called, the earliest one encountered will be considered first.
///
/// - parameter queue: the `DispatchQueue` on which the new `Deferred`'s notifications will be executed.
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Value, S: Sequence>(queue: DispatchQueue,
                                           deferreds: S, cancelOthers: Bool = false) -> Deferred<Value>
  where S.Iterator.Element: Deferred<Value>
{
  let first = TBD<Value>(queue: queue) {
    f in
    queue.async {
      var errors: [Deferred<Error>] = []
      deferreds.forEach {
        deferred in
        let error = TBD<Error> {
          e in
          deferred.notify {
            outcome in
            do {
              let value = try outcome.get()
              f.determine(value: value)
              e.cancel()
            }
            catch {
              e.determine(value: error)
            }
          }
          if cancelOthers { f.notify { _ in deferred.cancel() } }
      }
        errors.append(error)
      }

      if errors.isEmpty
      { // our sequence was empty
        let error = DeferredError.invalid("cannot find first determined value from an empty set in \(#function)")
        f.determine(error: error)
      }
      else
      {
        let combined = combine(queue: queue, deferreds: errors)
        combined.onValue { f.determine(error: $0.last!) }
        f.notify { _ in combined.cancel() }
      }
    }
  }

  return first
}

/// Return the first of an array of `Deferred`s to become determined.
///
/// Note that if the `Collection` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element has a value at the time
/// the function is called, the earliest one encountered will be considered first; if this
/// biasing is a problem, consider shuffling the collection first.
///
/// - parameter qos: the QoS at which the new `Deferred`'s notifications will be executed
/// - parameter deferreds: a `Collection` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstDetermined<Value, C: Collection>(qos: DispatchQoS,
                                                  deferreds: C, cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
  where C.Iterator.Element: Deferred<Value>
{
  let queue = DispatchQueue(label: "first-collection", qos: qos)
  return firstDetermined(queue: queue, deferreds: deferreds, cancelOthers: cancelOthers)
}

/// Return the first of an array of `Deferred`s to become determined.
///
/// Note that if the `Collection` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element has a value at the time
/// the function is called, the earliest one encountered will be considered first; if this
/// biasing is a problem, consider shuffling the collection first.
///
/// - parameter deferreds: a `Collection` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`, using a queue at the current QoS class.

public func firstDetermined<Value, C: Collection>(_ deferreds: C, cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
  where C.Iterator.Element: Deferred<Value>
{
  return firstDetermined(qos: .current, deferreds: deferreds, cancelOthers: cancelOthers)
}

/// Return the first of an array of `Deferred`s to become determined.
///
/// Note that if the `Collection` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element has a value at the time
/// the function is called, the earliest one encountered will be considered first; if this
/// biasing is a problem, consider shuffling the collection first.
///
/// - parameter queue: the `DispatchQueue` on which the new `Deferred`'s notifications will be executed.
/// - parameter deferreds: a `Collection` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstDetermined<Value, C: Collection>(queue: DispatchQueue,
                                                  deferreds: C, cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
  where C.Iterator.Element: Deferred<Value>
{
  if deferreds.count == 0
  {
    let error = DeferredError.invalid("cannot find first determined from an empty set in \(#function)")
    return Deferred(queue: queue, error: error)
  }

  let first = TBD<Deferred<Value>>(queue: queue) {
    f in
    deferreds.forEach {
      deferred in
      deferred.notify { _ in f.determine(value: deferred) }
      if cancelOthers { f.notify { _ in deferred.cancel() } }
    }
  }

  return first
}

/// Return the first of an array of `Deferred`s to become determined.
///
/// Note that if the `Sequence` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element is already determined at the time
/// the function is called, the earliest one encountered will be considered first.
///
/// - parameter qos: the QoS at which the new `Deferred`'s notifications will be executed
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstDetermined<Value, S: Sequence>(qos: DispatchQoS,
                                                deferreds: S, cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
  where S.Iterator.Element: Deferred<Value>
{
  let queue = DispatchQueue(label: "first-sequence", qos: qos)
  return firstDetermined(queue: queue, deferreds: deferreds, cancelOthers: cancelOthers)
}

/// Return the first of an array of `Deferred`s to become determined.
///
/// Note that if the `Sequence` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element is already determined at the time
/// the function is called, the earliest one encountered will be considered first.
///
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`, using a queue at the current QoS class.

public func firstDetermined<Value, S: Sequence>(_ deferreds: S, cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
where S.Iterator.Element: Deferred<Value>
{
  return firstDetermined(qos: .current, deferreds: deferreds, cancelOthers: cancelOthers)
}

/// Return the first of an array of `Deferred`s to become determined.
///
/// Note that if the `Sequence` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element is already determined at the time
/// the function is called, the earliest one encountered will be considered first.
///
/// - parameter queue: the `DispatchQueue` on which the new `Deferred`'s notifications will be executed.
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstDetermined<Value, S>(queue: DispatchQueue, deferreds: S,
                                      cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
  where S: Sequence, S.Iterator.Element: Deferred<Value>
{
  let first = TBD<Deferred<Value>>(queue: queue) {
    f in
    // We execute `Sequence.forEach` on a background thread
    // because nothing prevents S from blocking on `Sequence.next()`
    queue.async {
      var subscribed = false
      deferreds.forEach {
        deferred in
        subscribed = true
        deferred.notify { _ in f.determine(value: deferred) }
        if cancelOthers { f.notify { _ in deferred.cancel() } }
      }

      if !subscribed
      {
        let message = "cannot find first determined from an empty set in \(#function)"
        f.determine(error: DeferredError.invalid(message))
      }
    }
  }

  return first
}
