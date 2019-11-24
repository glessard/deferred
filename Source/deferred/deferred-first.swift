//
//  deferred-first.swift
//  deferred
//
//  Created by Guillaume Lessard on 10/9/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import Dispatch

struct NonEmptySequence<Element, S: Sequence>: Sequence, IteratorProtocol
  where S.Element == Element
{
  private var first: Element?
  private var iterator: S.Iterator

  init?(elements: S)
  {
    iterator = elements.makeIterator()
    guard let f = iterator.next() else { return nil }
    first = f
  }

  mutating func next() -> Element?
  {
    if let element = first
    {
      first = nil
      return element
    }
    else
    {
      return iterator.next()
    }
  }
}

/// Return the value of the `Deferred`s to be resolved successfully out of a `Sequence`.
///
/// The returned `Deferred` be resolved with an `Error` only if every input `Deferred`
/// is resolved with an `Error`; in such a situation the returned `Error` will be
/// the error returned by the last `Deferred` in the input `Sequence`.
///
/// If the `Sequence` is empty, this function will return `nil`.
/// If the `Sequence`'s `Iterator` can block on `next()`, this function could block
/// while attempting to retrieve the first element.
///
/// Note also that if more than one element is already resolved at the time
/// the function is called, the earliest one encountered will be considered first.
/// If such biasing is a problem, consider shuffling your sequence or collection first.
///
/// - parameter qos: the QoS at which the new `Deferred`'s notifications will be executed
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Success, Failure, S: Sequence>(_ deferreds: S, qos: DispatchQoS = .current,
                                                      cancelOthers: Bool = false) -> Deferred<Success, Failure>?
  where S.Element: Deferred<Success, Failure>
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
/// If the `Sequence` is empty, this function will return `nil`.
/// If the `Sequence`'s `Iterator` can block on `next()`, this function could block
/// while attempting to retrieve the first element.
///
/// Note also that if more than one element is already resolved at the time
/// the function is called, the earliest one encountered will be considered first.
/// If such biasing is a problem, consider shuffling your sequence or collection first.
///
/// - parameter queue: the `DispatchQueue` on which the new `Deferred`'s notifications will be executed.
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`).
///                           `cancelOthers` can only have an effect if `Deferred.Cancellation` can be represented as a `Failure`.
/// - returns: a new `Deferred`

public func firstValue<Success, Failure, S: Sequence>(_ deferreds: S, queue: DispatchQueue,
                                                      cancelOthers: Bool = false) -> Deferred<Success, Failure>?
  where S.Element: Deferred<Success, Failure>
{
  guard let deferreds = NonEmptySequence(elements: deferreds) else { return nil }

  return Deferred<Success, Failure>(queue: queue) {
    f in
    // We loop over the elements on a concurrent thread
    // because nothing prevents S from blocking on `S.Iterator.next()`
    DispatchQueue.global(qos: queue.qos.qosClass).async {
      var errors: [Deferred<Failure, Cancellation>] = []
      for deferred in deferreds
      {
        let error = Deferred<Failure, Cancellation> {
          e in
          deferred.notify {
            result in
            switch result
            {
            case .success(let value):
              f.resolve(value: value)
              e.cancel()
            case .failure(let error):
              e.resolve(value: error)
            }
          }
          if cancelOthers && (Cancellation.notSelected is Failure)
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

      assert(errors.isEmpty == false)
      let combined = combine(queue: queue, deferreds: errors)
      combined.notify { if let e = $0.value { f.resolve(error: e.last!) } }
      f.notify { combined.cancel() }
    }
  }
}

/// Return the first of an array of `Deferred`s to become resolved.
///
/// Note that if the `Sequence` is empty, the returned `Deferred` will contain an `Invalidation` error.
///
/// Note also that if more than one element is already resolved at the time
/// the function is called, the earliest one encountered will be considered first.
/// If such biasing is a problem, consider shuffling your sequence or collection first.
///
/// - parameter qos: the QoS at which the new `Deferred`'s notifications will be executed
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstResolved<Success, Failure, S: Sequence>(_ deferreds: S, qos: DispatchQoS = .current,
                                                         cancelOthers: Bool = false) -> Deferred<Deferred<Success, Failure>, Invalidation>
  where S.Element: Deferred<Success, Failure>
{
  let queue = DispatchQueue(label: "first-sequence", qos: qos)
  return firstResolved(deferreds, queue: queue, cancelOthers: cancelOthers)
}

/// Return the first of an array of `Deferred`s to become resolved.
///
/// Note that if the `Sequence` is empty, the returned `Deferred` will contain an `Invalidation` error.
///
/// Note also that if more than one element is already resolved at the time
/// the function is called, the earliest one encountered will be considered first.
/// If such biasing is a problem, consider shuffling your sequence or collection first.
///
/// - parameter queue: the `DispatchQueue` on which the new `Deferred`'s notifications will be executed.
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstResolved<Success, Failure, S>(_ deferreds: S, queue: DispatchQueue,
                                               cancelOthers: Bool = false) -> Deferred<Deferred<Success, Failure>, Invalidation>
  where S: Sequence, S.Element: Deferred<Success, Failure>
{
  let function = #function

  return Deferred<Deferred<Success, Failure>, Invalidation>(queue: queue) {
    resolver in
    // We loop over the elements on a concurrent thread
    // because nothing prevents S from blocking on `S.Iterator.next()`
    DispatchQueue.global(qos: queue.qos.qosClass).async {
      guard let deferreds = NonEmptySequence(elements: deferreds)
        else {
          resolver.resolve(error: .invalid("cannot find first resolved `Deferred` from an empty sequence in \(function)"))
          return
      }

      for deferred in deferreds
      {
        deferred.notify {
          [weak deferred] _ in
          if let d = deferred
          {
            resolver.resolve(value: d)
          }
        }
        if cancelOthers && (Cancellation.notSelected is Failure)
        {
          resolver.notify { deferred.cancel(.notSelected) }
        }
        else
        {
          resolver.retainSource(deferred)
        }
      }
    }
  }
}

/// match any `AnyObject` reference to its corresponding `ObjectIdentifier`

private func ~= <T: AnyObject>(object: T, id: ObjectIdentifier?) -> Bool
{
  return ObjectIdentifier(object) == id
}

public func firstResolved<T1, F1, T2, F2>(_ d1: Deferred<T1, F1>,
                                          _ d2: Deferred<T2, F2>,
                                          canceling: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>)
{
  let (r1, o1) = Deferred<T1, Error>.CreatePair(queue: d1.queue)
  let (r2, o2) = Deferred<T2, Error>.CreatePair(queue: d2.queue)

  // find which input gets resolved first
  let selected = Deferred<ObjectIdentifier, Never>() {
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
    case d1: r1.resolve(d1.result.withAnyError)
    case d2: r2.resolve(d2.result.withAnyError)
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

public func firstResolved<T1, F1, T2, F2, T3, F3>(_ d1: Deferred<T1, F1>,
                                                  _ d2: Deferred<T2, F2>,
                                                  _ d3: Deferred<T3, F3>,
                                                  canceling: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>, Deferred<T3, Error>)
{
  let (r1, o1) = Deferred<T1, Error>.CreatePair(queue: d1.queue)
  let (r2, o2) = Deferred<T2, Error>.CreatePair(queue: d2.queue)
  let (r3, o3) = Deferred<T3, Error>.CreatePair(queue: d3.queue)

  // find which input gets resolved first
  let selected = Deferred<ObjectIdentifier, Never>() {
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
    case d1: r1.resolve(d1.result.withAnyError)
    case d2: r2.resolve(d2.result.withAnyError)
    case d3: r3.resolve(d3.result.withAnyError)
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

public func firstResolved<T1, F1, T2, F2, T3, F3, T4, F4>(_ d1: Deferred<T1, F1>,
                                                          _ d2: Deferred<T2, F2>,
                                                          _ d3: Deferred<T3, F3>,
                                                          _ d4: Deferred<T4, F4>,
                                                          canceling: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>, Deferred<T3, Error>, Deferred<T4, Error>)
{
  let (r1, o1) = Deferred<T1, Error>.CreatePair(queue: d1.queue)
  let (r2, o2) = Deferred<T2, Error>.CreatePair(queue: d2.queue)
  let (r3, o3) = Deferred<T3, Error>.CreatePair(queue: d3.queue)
  let (r4, o4) = Deferred<T4, Error>.CreatePair(queue: d4.queue)

  // find which input gets resolved first
  let selected = Deferred<ObjectIdentifier, Never>() {
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
    case d1: r1.resolve(d1.result.withAnyError)
    case d2: r2.resolve(d2.result.withAnyError)
    case d3: r3.resolve(d3.result.withAnyError)
    case d4: r4.resolve(d4.result.withAnyError)
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

private func resolveValue<T, F>(_ resolver: Resolver<ObjectIdentifier, Cancellation>,
                                _ deferred: Deferred<T, F>) -> Deferred<Error, Cancellation>
{
  return Deferred<Error, Cancellation> {
    error in
    let id = ObjectIdentifier(deferred)
    deferred.notify {
      result in
      switch result
      {
      case .success:
        resolver.resolve(value: id)
        error.cancel()
      case .failure(let e):
        error.resolve(value: e)
      }
    }
    resolver.retainSource(deferred)
  }
}

public func firstValue<T1, F1, T2, F2>(_ d1: Deferred<T1, F1>,
                                       _ d2: Deferred<T2, F2>,
                                       canceling: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>)
{
  let (r1, o1) = Deferred<T1, Error>.CreatePair(queue: d1.queue)
  let (r2, o2) = Deferred<T2, Error>.CreatePair(queue: d2.queue)

  // find which input first gets a value
  let selected = Deferred<ObjectIdentifier, Cancellation>() {
    resolver in
    let errors = [
      resolveValue(resolver, d1),
      resolveValue(resolver, d2),
    ]

    // figure out whether all inputs got errors
    let combined = combine(qos: .utility, deferreds: errors)
    combined.notify { if $0.isValue { resolver.resolve(error: .notSelected) } }
    resolver.notify { combined.cancel() }
  }

  selected.notify {
    result in
    if canceling
    { // attempt to cancel the unresolved input
      d1.cancel(.notSelected)
      d2.cancel(.notSelected)
    }

    switch result
    {
    case .success(let id):
      switch id
      { // transfer the value-containing result to the selected output
      case d1: r1.resolve(d1.result.withAnyError)
      case d2: r2.resolve(d2.result.withAnyError)
      default: fatalError()
      }
    case .failure:
      // all inputs got errors, so transfer them to the outputs
      d1.error.map { _ = r1.resolve(error: $0) }
      d2.error.map { _ = r2.resolve(error: $0) }
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

public func firstValue<T1, F1, T2, F2, T3, F3>(_ d1: Deferred<T1, F1>,
                                               _ d2: Deferred<T2, F2>,
                                               _ d3: Deferred<T3, F3>,
                                               canceling: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>, Deferred<T3, Error>)
{
  let (r1, o1) = Deferred<T1, Error>.CreatePair(queue: d1.queue)
  let (r2, o2) = Deferred<T2, Error>.CreatePair(queue: d2.queue)
  let (r3, o3) = Deferred<T3, Error>.CreatePair(queue: d3.queue)

  // find which input first gets a value
  let selected = Deferred<ObjectIdentifier, Cancellation>() {
    resolver in
    let errors = [
      resolveValue(resolver, d1),
      resolveValue(resolver, d2),
      resolveValue(resolver, d3),
    ]

    // figure out whether all inputs got errors
    let combined = combine(qos: .utility, deferreds: errors)
    combined.notify { if $0.isValue { resolver.resolve(error: .notSelected) } }
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

    switch result
    {
    case .success(let id):
      switch id
      { // transfer the value-containing result to the selected output
      case d1: r1.resolve(d1.result.withAnyError)
      case d2: r2.resolve(d2.result.withAnyError)
      case d3: r3.resolve(d3.result.withAnyError)
      default: fatalError()
      }
    case .failure:
      // all inputs got errors, so transfer them to the outputs
      d1.error.map { _ = r1.resolve(error: $0) }
      d2.error.map { _ = r2.resolve(error: $0) }
      d3.error.map { _ = r3.resolve(error: $0) }
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

public func firstValue<T1, F1, T2, F2, T3, F3, T4, F4>(_ d1: Deferred<T1, F1>,
                                                       _ d2: Deferred<T2, F2>,
                                                       _ d3: Deferred<T3, F3>,
                                                       _ d4: Deferred<T4, F4>,
                                                       canceling: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>, Deferred<T3, Error>, Deferred<T4, Error>)
{
  let (r1, o1) = Deferred<T1, Error>.CreatePair(queue: d1.queue)
  let (r2, o2) = Deferred<T2, Error>.CreatePair(queue: d2.queue)
  let (r3, o3) = Deferred<T3, Error>.CreatePair(queue: d3.queue)
  let (r4, o4) = Deferred<T4, Error>.CreatePair(queue: d4.queue)

  // find which input first gets a value
  let selected = Deferred<ObjectIdentifier, Cancellation>() {
    resolver in
    let errors = [
      resolveValue(resolver, d1),
      resolveValue(resolver, d2),
      resolveValue(resolver, d3),
      resolveValue(resolver, d4),
      ]

    // figure out whether all inputs got errors
    let combined = combine(qos: .utility, deferreds: errors)
    combined.notify { if $0.isValue { resolver.resolve(error: .notSelected) } }
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

    switch result
    {
    case .success(let id):
      switch id
      { // transfer the value-containing result to the selected output
      case d1: r1.resolve(d1.result.withAnyError)
      case d2: r2.resolve(d2.result.withAnyError)
      case d3: r3.resolve(d3.result.withAnyError)
      case d4: r4.resolve(d4.result.withAnyError)
    default: fatalError()
      }
    case .failure:
      // all inputs got errors, so transfer them to the outputs
      d1.error.map { _ = r1.resolve(error: $0) }
      d2.error.map { _ = r2.resolve(error: $0) }
      d3.error.map { _ = r3.resolve(error: $0) }
      d4.error.map { _ = r4.resolve(error: $0) }
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
