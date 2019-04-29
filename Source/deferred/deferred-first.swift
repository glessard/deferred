//
//  deferred-first.swift
//  deferred
//
//  Created by Guillaume Lessard on 10/9/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import Dispatch

/// Return the value of the first of an array of `Deferred`s to be resolved succesfully.
///
/// The returned `Deferred` be resolved with an `Error` only if every input `Deferred`
/// is resolved with an `Error`; in such a situation the returned `Error` will be
/// the last one to have been resolved.
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
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Value, C: Collection>(_ deferreds: C, qos: DispatchQoS = .current,
                                             cancelOthers: Bool = false) -> Deferred<Value>
  where C.Element: Deferred<Value>
{
  let queue = DispatchQueue(label: "first-collection", qos: qos)
  return firstValue(deferreds, queue: queue, cancelOthers: cancelOthers)
}

/// Return the value of the first of an array of `Deferred`s to be resolved succesfully.
///
/// The returned `Deferred` be resolved with an `Error` only if every input `Deferred`
/// is resolved with an `Error`; in such a situation the returned `Error` will be
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
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Value, C: Collection>(_ deferreds: C, queue: DispatchQueue,
                                             cancelOthers: Bool = false) -> Deferred<Value>
  where C.Element: Deferred<Value>
{
  if deferreds.isEmpty
  {
    let error = DeferredError.invalid("cannot find first resolved value from an empty set in \(#function)")
    return Deferred(queue: queue, error: error)
  }

  return TBD<Value>(queue: queue) {
    f in
    var errors: [Deferred<Error>] = []
    errors.reserveCapacity(deferreds.count)

    deferreds.forEach {
      deferred in
      let e = TBD<Error>() {
        e in
        deferred.notify {
          result in
          do {
            let value = try result.get()
            f.resolve(value: value)
            e.cancel()
          }
          catch {
            e.resolve(value: error)
          }
        }
        if cancelOthers
        {
          f.notify { deferred.cancel(.notSelected) }
        }
        else
        {
          f.retainSource(deferred)
        }
      }
      errors.append(e)
    }

    let combined = combine(queue: queue, deferreds: errors)
    combined.notify { if let e = $0.value { f.resolve(error: e.last!) } }
    f.notify { combined.cancel() }
  }
}

/// Return the value of the `Deferred`s to be resolved successfully out of a `Sequence`.
///
/// The returned `Deferred` be resolved with an `Error` only if every input `Deferred`
/// is resolved with an `Error`; in such a situation the returned `Error` will be
/// the error returned by the last `Deferred` in the input `Sequence`.
///
/// Note that if the `Sequence` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element is already resolved at the time
/// the function is called, the earliest one encountered will be considered first.
///
/// - parameter qos: the QoS at which the new `Deferred`'s notifications will be executed
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Value, S: Sequence>(_ deferreds: S, qos: DispatchQoS = .current,
                                           cancelOthers: Bool = false) -> Deferred<Value>
  where S.Element: Deferred<Value>
{
  let queue = DispatchQueue(label: "first-sequence", qos: qos)
  return firstValue(deferreds, queue: queue, cancelOthers: cancelOthers)
}

/// Return the value of the `Deferred`s to be resolved successfully out of a `Sequence`.
///
/// The returned `Deferred` be resolved with an `Error` only if every input `Deferred`
/// is resolved with an `Error`; in such a situation the returned `Error` will be
/// the error returned by the last `Deferred` in the input `Sequence`.
///
/// Note that if the `Sequence` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element is already resolved at the time
/// the function is called, the earliest one encountered will be considered first.
///
/// - parameter queue: the `DispatchQueue` on which the new `Deferred`'s notifications will be executed.
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Value, S: Sequence>(_ deferreds: S, queue: DispatchQueue,
                                           cancelOthers: Bool = false) -> Deferred<Value>
  where S.Element: Deferred<Value>
{
  return TBD<Value>(queue: queue) {
    f in
    queue.async {
      var errors: [Deferred<Error>] = []
      deferreds.forEach {
        deferred in
        let error = TBD<Error> {
          e in
          deferred.notify {
            result in
            do {
              let value = try result.get()
              f.resolve(value: value)
              e.cancel()
            }
            catch {
              e.resolve(value: error)
            }
          }
          if cancelOthers
          {
            f.notify { deferred.cancel(.notSelected) }
          }
          else
          {
            f.retainSource(deferred)
          }
        }
        errors.append(error)
      }

      if errors.isEmpty
      { // our sequence was empty
        let error = DeferredError.invalid("cannot find first resolved value from an empty set in \(#function)")
        f.resolve(error: error)
      }
      else
      {
        let combined = combine(queue: queue, deferreds: errors)
        combined.notify { if let e = $0.value { f.resolve(error: e.last!) } }
        f.notify { combined.cancel() }
      }
    }
  }
}

/// Return the first of an array of `Deferred`s to become resolved.
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
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstResolved<Value, C: Collection>(_ deferreds: C, qos: DispatchQoS = .current,
                                                cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
  where C.Element: Deferred<Value>
{
  let queue = DispatchQueue(label: "first-collection", qos: qos)
  return firstResolved(deferreds, queue: queue, cancelOthers: cancelOthers)
}

/// Return the first of an array of `Deferred`s to become resolved.
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
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstResolved<Value, C: Collection>(_ deferreds: C, queue: DispatchQueue,
                                                cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
  where C.Element: Deferred<Value>
{
  if deferreds.count == 0
  {
    let error = DeferredError.invalid("cannot find first resolved from an empty set in \(#function)")
    return Deferred(queue: queue, error: error)
  }

  let first = TBD<Deferred<Value>>(queue: queue) {
    resolver in
    deferreds.forEach {
      deferred in
      deferred.notify {
        [weak deferred] _ in
        if let d = deferred
        {
          resolver.resolve(value: d)
        }
      }
      if cancelOthers
      {
        resolver.notify { deferred.cancel(.notSelected) }
      }
      else
      {
        resolver.retainSource(deferred)
      }
    }
  }

  return first
}

/// Return the first of an array of `Deferred`s to become resolved.
///
/// Note that if the `Sequence` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element is already resolved at the time
/// the function is called, the earliest one encountered will be considered first.
///
/// - parameter qos: the QoS at which the new `Deferred`'s notifications will be executed
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstResolved<Value, S: Sequence>(_ deferreds: S, qos: DispatchQoS = .current,
                                              cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
  where S.Element: Deferred<Value>
{
  let queue = DispatchQueue(label: "first-sequence", qos: qos)
  return firstResolved(deferreds, queue: queue, cancelOthers: cancelOthers)
}

/// Return the first of an array of `Deferred`s to become resolved.
///
/// Note that if the `Sequence` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note also that if more than one element is already resolved at the time
/// the function is called, the earliest one encountered will be considered first.
///
/// - parameter queue: the `DispatchQueue` on which the new `Deferred`'s notifications will be executed.
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstResolved<Value, S>(_ deferreds: S, queue: DispatchQueue,
                                    cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
  where S: Sequence, S.Element: Deferred<Value>
{
  let first = TBD<Deferred<Value>>(queue: queue) {
    resolver in
    // We execute `Sequence.forEach` on a background thread
    // because nothing prevents S from blocking on `Sequence.next()`
    queue.async {
      var empty = true
      for deferred in deferreds
      {
        empty = false
        deferred.notify {
          [weak deferred] _ in
          if let d = deferred
          {
            resolver.resolve(value: d)
          }
        }
        if cancelOthers
        {
          resolver.notify { deferred.cancel(.notSelected) }
        }
        else
        {
          resolver.retainSource(deferred)
        }
      }

      if empty
      {
        let message = "cannot find first resolved from an empty set in \(#function)"
        resolver.resolve(error: DeferredError.invalid(message))
      }
    }
  }

  return first
}
