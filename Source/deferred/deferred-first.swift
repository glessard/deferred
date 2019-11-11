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

public func firstValue<Success, C: Collection>(_ deferreds: C, qos: DispatchQoS = .current,
                                             cancelOthers: Bool = false) -> Deferred<Success>
  where C.Element: Deferred<Success>
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

public func firstValue<Success, C: Collection>(_ deferreds: C, queue: DispatchQueue,
                                             cancelOthers: Bool = false) -> Deferred<Success>
  where C.Element: Deferred<Success>
{
  if deferreds.isEmpty
  {
    let error = DeferredError.invalid("cannot find first resolved value from an empty set in \(#function)")
    return Deferred(queue: queue, error: error)
  }

  return TBD<Success>(queue: queue) {
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

public func firstValue<Success, S: Sequence>(_ deferreds: S, qos: DispatchQoS = .current,
                                           cancelOthers: Bool = false) -> Deferred<Success>
  where S.Element: Deferred<Success>
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

public func firstValue<Success, S: Sequence>(_ deferreds: S, queue: DispatchQueue,
                                           cancelOthers: Bool = false) -> Deferred<Success>
  where S.Element: Deferred<Success>
{
  return TBD<Success>(queue: queue) {
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

public func firstResolved<Success, C: Collection>(_ deferreds: C, qos: DispatchQoS = .current,
                                                cancelOthers: Bool = false) -> Deferred<Deferred<Success>>
  where C.Element: Deferred<Success>
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

public func firstResolved<Success, C: Collection>(_ deferreds: C, queue: DispatchQueue,
                                                cancelOthers: Bool = false) -> Deferred<Deferred<Success>>
  where C.Element: Deferred<Success>
{
  if deferreds.count == 0
  {
    let error = DeferredError.invalid("cannot find first resolved from an empty set in \(#function)")
    return Deferred(queue: queue, error: error)
  }

  let first = TBD<Deferred<Success>>(queue: queue) {
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

public func firstResolved<Success, S: Sequence>(_ deferreds: S, qos: DispatchQoS = .current,
                                              cancelOthers: Bool = false) -> Deferred<Deferred<Success>>
  where S.Element: Deferred<Success>
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

public func firstResolved<Success, S>(_ deferreds: S, queue: DispatchQueue,
                                    cancelOthers: Bool = false) -> Deferred<Deferred<Success>>
  where S: Sequence, S.Element: Deferred<Success>
{
  let first = TBD<Deferred<Success>>(queue: queue) {
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

/// match any `AnyObject` reference to its corresponding `ObjectIdentifier`

private func ~= <T: AnyObject>(object: T, id: ObjectIdentifier?) -> Bool
{
  return ObjectIdentifier(object) == id
}

public func firstResolved<T1, T2>(_ d1: Deferred<T1>, _ d2: Deferred<T2>,
                                  canceling: Bool = false) -> (Deferred<T1>, Deferred<T2>)
{
  let (r1, o1) = TBD<T1>.CreatePair(queue: d1.queue)
  let (r2, o2) = TBD<T2>.CreatePair(queue: d2.queue)

  // find which input gets resolved first
  let selected = TBD<ObjectIdentifier>() {
    resolver in
    d1.notify { [id = ObjectIdentifier(d1)] _ in resolver.resolve(value: id) }
    d2.notify { [id = ObjectIdentifier(d2)] _ in resolver.resolve(value: id) }
  }

  selected.notify {
    result in
    if canceling
    { // attempt to cancel the unresolved input
      d1.cancel(.notSelected)
      d2.cancel(.notSelected)
    }

    switch result.value
    { // transfer the result to the selected output
    case d1: r1.resolve(d1.result)
    case d2: r2.resolve(d2.result)
    default: fatalError()
    }

    // cancel the remaining unresolved output
    r1.cancel(.notSelected)
    r2.cancel(.notSelected)
  }

  // ensure `selected` lasts as long as it will be useful
  r1.retainSource(selected)
  r2.retainSource(selected)
  return (o1, o2)
}

public func firstResolved<T1, T2, T3>(_ d1: Deferred<T1>, _ d2: Deferred<T2>, _ d3: Deferred<T3>,
                                      canceling: Bool = false) -> (Deferred<T1>, Deferred<T2>, Deferred<T3>)
{
  let (r1, o1) = TBD<T1>.CreatePair(queue: d1.queue)
  let (r2, o2) = TBD<T2>.CreatePair(queue: d2.queue)
  let (r3, o3) = TBD<T3>.CreatePair(queue: d3.queue)

  // find which input gets resolved first
  let selected = TBD<ObjectIdentifier>() {
    resolver in
    d1.notify { [id = ObjectIdentifier(d1)] _ in resolver.resolve(value: id) }
    d2.notify { [id = ObjectIdentifier(d2)] _ in resolver.resolve(value: id) }
    d3.notify { [id = ObjectIdentifier(d3)] _ in resolver.resolve(value: id) }
  }

  selected.notify {
    result in
    if canceling
    { // attempt to cancel the unresolved inputs
      d1.cancel(.notSelected)
      d2.cancel(.notSelected)
      d3.cancel(.notSelected)
    }

    switch result.value
    { // transfer the result to the selected output
    case d1: r1.resolve(d1.result)
    case d2: r2.resolve(d2.result)
    case d3: r3.resolve(d3.result)
    default: fatalError()
    }

    // cancel the remaining unresolved outputs
    r1.cancel(.notSelected)
    r2.cancel(.notSelected)
    r3.cancel(.notSelected)
  }

  // ensure `selected` lasts as long as it will be useful
  r1.retainSource(selected)
  r2.retainSource(selected)
  r3.retainSource(selected)
  return (o1, o2, o3)
}

public func firstResolved<T1, T2, T3, T4>(_ d1: Deferred<T1>, _ d2: Deferred<T2>, _ d3: Deferred<T3>, _ d4: Deferred<T4>,
                                          canceling: Bool = false) -> (Deferred<T1>, Deferred<T2>, Deferred<T3>, Deferred<T4>)
{
  let (r1, o1) = TBD<T1>.CreatePair(queue: d1.queue)
  let (r2, o2) = TBD<T2>.CreatePair(queue: d2.queue)
  let (r3, o3) = TBD<T3>.CreatePair(queue: d3.queue)
  let (r4, o4) = TBD<T4>.CreatePair(queue: d4.queue)

  // find which input gets resolved first
  let selected = TBD<ObjectIdentifier>() {
    resolver in
    d1.notify { [id = ObjectIdentifier(d1)] _ in resolver.resolve(value: id) }
    d2.notify { [id = ObjectIdentifier(d2)] _ in resolver.resolve(value: id) }
    d3.notify { [id = ObjectIdentifier(d3)] _ in resolver.resolve(value: id) }
    d4.notify { [id = ObjectIdentifier(d4)] _ in resolver.resolve(value: id) }
  }

  selected.notify {
    result in
    if canceling
    { // attempt to cancel the unresolved inputs
      d1.cancel(.notSelected)
      d2.cancel(.notSelected)
      d3.cancel(.notSelected)
      d4.cancel(.notSelected)
    }

    switch result.value
    { // transfer the result to the selected output
    case d1: r1.resolve(d1.result)
    case d2: r2.resolve(d2.result)
    case d3: r3.resolve(d3.result)
    case d4: r4.resolve(d4.result)
    default: fatalError()
    }

    // cancel the remaining unresolved outputs
    r1.cancel(.notSelected)
    r2.cancel(.notSelected)
    r3.cancel(.notSelected)
    r4.cancel(.notSelected)
  }

  // ensure `selected` lasts as long as it will be useful
  r1.retainSource(selected)
  r2.retainSource(selected)
  r3.retainSource(selected)
  r4.retainSource(selected)
  return (o1, o2, o3, o4)
}

private func resolveValue<T>(_ resolver: Resolver<ObjectIdentifier, Error>,
                             _ deferred: Deferred<T>) -> Deferred<Error>
{
  return TBD<Error> {
    error in
    let id = ObjectIdentifier(deferred)
    deferred.notify {
      result in
      do {
        _ = try result.get()
        resolver.resolve(value: id)
        error.cancel()
      }
      catch let e {
        error.resolve(value: e)
      }
    }
    resolver.retainSource(deferred)
  }
}

public func firstValue<T1, T2>(_ d1: Deferred<T1>, _ d2: Deferred<T2>,
                               canceling: Bool = false) -> (Deferred<T1>, Deferred<T2>)
{
  let (r1, o1) = TBD<T1>.CreatePair(queue: d1.queue)
  let (r2, o2) = TBD<T2>.CreatePair(queue: d2.queue)

  // find which input first gets a value
  let selected = TBD<ObjectIdentifier>() {
    resolver in
    let errors = [
      resolveValue(resolver, d1),
      resolveValue(resolver, d2),
    ]

    // figure out whether all inputs got errors
    let combined = combine(qos: .utility, deferreds: errors)
    combined.notify { if $0.isValue { resolver.resolve(error: DeferredError.notSelected) } }
    resolver.notify { combined.cancel() }
  }

  selected.notify {
    result in
    if canceling
    { // attempt to cancel the unresolved input
      d1.cancel(.notSelected)
      d2.cancel(.notSelected)
    }

    switch result.value
    { // transfer the value-containing result to the selected output
    case d1?: r1.resolve(d1.result)
    case d2?: r2.resolve(d2.result)
    case nil:
      // all inputs got errors, so transfer them to the outputs
      d1.error.map { _ = r1.resolve(error: $0) }
      d2.error.map { _ = r2.resolve(error: $0) }
    default: fatalError()
    }

    // cancel the remaining unresolved outputs
    r1.cancel(.notSelected)
    r2.cancel(.notSelected)
  }

  // ensure `selected` lasts as long as it will be useful
  r1.retainSource(selected)
  r2.retainSource(selected)
  return (o1, o2)
}

public func firstValue<T1, T2, T3>(_ d1: Deferred<T1>, _ d2: Deferred<T2>, _ d3: Deferred<T3>,
                                   canceling: Bool = false) -> (Deferred<T1>, Deferred<T2>, Deferred<T3>)
{
  let (r1, o1) = TBD<T1>.CreatePair(queue: d1.queue)
  let (r2, o2) = TBD<T2>.CreatePair(queue: d2.queue)
  let (r3, o3) = TBD<T3>.CreatePair(queue: d3.queue)

  // find which input first gets a value
  let selected = TBD<ObjectIdentifier>() {
    resolver in
    let errors = [
      resolveValue(resolver, d1),
      resolveValue(resolver, d2),
      resolveValue(resolver, d3),
    ]

    // figure out whether all inputs got errors
    let combined = combine(qos: .utility, deferreds: errors)
    combined.notify { if $0.isValue { resolver.resolve(error: DeferredError.notSelected) } }
    resolver.notify { combined.cancel() }
  }

  selected.notify {
    result in
    if canceling
    { // attempt to cancel any unresolved inputs
      d1.cancel(.notSelected)
      d2.cancel(.notSelected)
      d3.cancel(.notSelected)
    }

    switch result.value
    { // transfer the value-containing result to the selected output
    case d1?: r1.resolve(d1.result)
    case d2?: r2.resolve(d2.result)
    case d3?: r3.resolve(d3.result)
    case nil:
      // all inputs got errors, so transfer them to the outputs
      d1.error.map { _ = r1.resolve(error: $0) }
      d2.error.map { _ = r2.resolve(error: $0) }
      d3.error.map { _ = r3.resolve(error: $0) }
    default: fatalError()
    }

    // cancel the remaining unresolved outputs
    r1.cancel(.notSelected)
    r2.cancel(.notSelected)
    r3.cancel(.notSelected)
  }

  // ensure `selected` lasts as long as it will be useful
  r1.retainSource(selected)
  r2.retainSource(selected)
  r3.retainSource(selected)
  return (o1, o2, o3)
}

public func firstValue<T1, T2, T3, T4>(_ d1: Deferred<T1>, _ d2: Deferred<T2>, _ d3: Deferred<T3>, _ d4: Deferred<T4>,
                                       canceling: Bool = false) -> (Deferred<T1>, Deferred<T2>, Deferred<T3>, Deferred<T4>)
{
  let (r1, o1) = TBD<T1>.CreatePair(queue: d1.queue)
  let (r2, o2) = TBD<T2>.CreatePair(queue: d2.queue)
  let (r3, o3) = TBD<T3>.CreatePair(queue: d3.queue)
  let (r4, o4) = TBD<T4>.CreatePair(queue: d4.queue)

  // find which input first gets a value
  let selected = TBD<ObjectIdentifier>() {
    resolver in
    let errors = [
      resolveValue(resolver, d1),
      resolveValue(resolver, d2),
      resolveValue(resolver, d3),
      resolveValue(resolver, d4),
      ]

    // figure out whether all inputs got errors
    let combined = combine(qos: .utility, deferreds: errors)
    combined.notify { if $0.isValue { resolver.resolve(error: DeferredError.notSelected) } }
    resolver.notify { combined.cancel() }
  }

  selected.notify {
    result in
    if canceling
    { // attempt to cancel any unresolved inputs
      d1.cancel(.notSelected)
      d2.cancel(.notSelected)
      d3.cancel(.notSelected)
      d4.cancel(.notSelected)
    }

    switch result.value
    { // transfer the value-containing result to the selected output
    case d1?: r1.resolve(d1.result)
    case d2?: r2.resolve(d2.result)
    case d3?: r3.resolve(d3.result)
    case d4?: r4.resolve(d4.result)
    case nil:
      // all inputs got errors, so transfer them to the outputs
      d1.error.map { _ = r1.resolve(error: $0) }
      d2.error.map { _ = r2.resolve(error: $0) }
      d3.error.map { _ = r3.resolve(error: $0) }
      d4.error.map { _ = r4.resolve(error: $0) }
    default: fatalError()
    }

    // cancel the remaining unresolved outputs
    r1.cancel(.notSelected)
    r2.cancel(.notSelected)
    r3.cancel(.notSelected)
    r4.cancel(.notSelected)
  }

  // ensure `selected` lasts as long as it will be useful
  r1.retainSource(selected)
  r2.retainSource(selected)
  r3.retainSource(selected)
  r4.retainSource(selected)
  return (o1, o2, o3, o4)
}
