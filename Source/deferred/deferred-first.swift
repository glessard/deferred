//
//  deferred-first.swift
//  deferred
//
//  Created by Guillaume Lessard on 10/9/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import Dispatch

private func resolveFirstValue<T, F>(_ value: Resolver<T, F>,
                                     _ error: Resolver<F, Never>,
                                     _ deferred: Deferred<T, F>)
  where F: Error
{
  deferred.notify {
    result in
    switch result
    {
    case .success(let v):
      value.resolve(value: v)
    case .failure(let e):
      error.resolve(value: e)
    }
  }
}

/// Return the value of the first of an array of `Deferred`s to be resolved succesfully.
///
/// The returned `Deferred` be resolved with an `Error` only if every input `Deferred`
/// is resolved with an `Error`; in such a situation the returned `Error` will be
/// the last one to have been resolved.
///
/// Note that if the `Collection` is empty, the resulting `Deferred` will resolve to a
/// `DeferredError.invalid` error.
///
/// Note that if more than one element has a value at the time
/// the function is called, the earliest one encountered will be considered first; if this
/// biasing is a problem, consider shuffling the collection first.
///
/// - parameter qos: the QoS at which the new `Deferred`'s notifications will be executed
/// - parameter deferreds: a `Collection` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Success, Failure, C: Collection>(_ deferreds: C, qos: DispatchQoS = .current,
                                                        cancelOthers: Bool = false) -> Deferred<Success, Failure>?
  where C.Element: Deferred<Success, Failure>
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
/// Note that if more than one element has a value at the time
/// the function is called, the earliest one encountered will be considered first; if this
/// biasing is a problem, consider shuffling the collection first.
///
/// - parameter queue: the `DispatchQueue` on which the new `Deferred`'s notifications will be executed.
/// - parameter deferreds: a `Collection` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Success, Failure, C: Collection>(_ deferreds: C, queue: DispatchQueue,
                                                        cancelOthers: Bool = false) -> Deferred<Success, Failure>?
  where C.Element: Deferred<Success, Failure>
{
  if deferreds.isEmpty { return nil }

  return Deferred<Success, Failure>(queue: queue) {
    first in
    let errors = deferreds.map {
      deferred in
      Deferred<Failure, Never>(queue: deferred.queue) {
        error in
        resolveFirstValue(first, error, deferred)
      }
    }

    let combined = combine(queue: queue, deferreds: errors)
    combined.notify { if let e = $0.value { first.resolve(error: e.last!) } }

    // clean up (closure also retains sources)
    first.notify {
      withExtendedLifetime(combined) {}
      if cancelOthers { deferreds.forEach { $0.cancel(.notSelected) } }
    }
  }
}

private struct NonEmptySequence<Element, S: Sequence>: Sequence, IteratorProtocol
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
    return iterator.next()
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
/// Note that if more than one element is already resolved at the time
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
/// Note that if more than one element is already resolved at the time
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
    first in
    // We loop over the elements on a concurrent thread
    // because nothing prevents S from blocking on `S.Iterator.next()`
    DispatchQueue.global(qos: queue.qos.qosClass).async {
      var values: [Deferred<Success, Failure>] = []
      var errors: [Deferred<Failure, Never>] = []
      for deferred in deferreds
      {
        let error = Deferred<Failure, Never>(queue: deferred.queue) {
          error in
          resolveFirstValue(first, error, deferred)
        }
        values.append(deferred)
        errors.append(error)
      }

      assert(errors.isEmpty == false)
      let combined = combine(queue: queue, deferreds: errors)
      combined.notify { if let e = $0.value { first.resolve(error: e.last!) } }

      // clean up (closure also retains sources)
      first.notify {
        withExtendedLifetime(combined) {}
        if cancelOthers { values.forEach { $0.cancel(.notSelected) } }
      }
    }
  }
}

/// Return the first of an array of `Deferred`s to become resolved.
///
/// If the `Collection` is empty, this function will return `nil`.
///
/// Note  that if more than one element has a value at the time
/// the function is called, the earliest one encountered will be considered first; if this
/// biasing is a problem, consider shuffling the collection first.
///
/// - parameter qos: the QoS at which the new `Deferred`'s notifications will be executed
/// - parameter deferreds: a `Collection` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstResolved<Success, Failure, C>(_ deferreds: C, qos: DispatchQoS = .current,
                                               cancelOthers: Bool = false) -> Deferred<Success, Failure>?
  where C: Collection, C.Element: Deferred<Success, Failure>
{
  let queue = DispatchQueue(label: "first-collection", qos: qos)
  return firstResolved(deferreds, queue: queue, cancelOthers: cancelOthers)
}

/// Return the first of an array of `Deferred`s to become resolved.
///
/// If the `Collection` is empty, this function will return `nil`.
///
/// Note that if more than one element has a value at the time
/// the function is called, the earliest one encountered will be considered first; if this
/// biasing is a problem, consider shuffling the collection first.
///
/// - parameter queue: the `DispatchQueue` on which the new `Deferred`'s notifications will be executed.
/// - parameter deferreds: a `Collection` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstResolved<Success, Failure, C>(_ deferreds: C, queue: DispatchQueue,
                                               cancelOthers: Bool = false) -> Deferred<Success, Failure>?
  where C: Collection, C.Element: Deferred<Success, Failure>
{
  if deferreds.count == 0 { return nil }

  return Deferred<Success, Failure>(queue: queue) {
    first in
    let deferreds = Array(deferreds)
    for deferred in deferreds { deferred.notify { first.resolve($0) } }

    // clean up (closure also retains sources)
    first.notify { if cancelOthers { deferreds.forEach { $0.cancel(.notSelected) } } }
  }
}

/// Return the first of an array of `Deferred`s to become resolved.
///
/// If the `Sequence` is empty, this function will return `nil`.
/// If the `Sequence`'s `Iterator` can block on `next()`, this function could block
/// while attempting to retrieve the first element.
///
/// Note that if more than one element is already resolved at the time
/// the function is called, the earliest one encountered will be considered first.
///
/// - parameter qos: the QoS at which the new `Deferred`'s notifications will be executed
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstResolved<Success, Failure, S: Sequence>(_ deferreds: S, qos: DispatchQoS = .current,
                                                         cancelOthers: Bool = false) -> Deferred<Success, Failure>?
  where S.Element: Deferred<Success, Failure>
{
  let queue = DispatchQueue(label: "first-sequence", qos: qos)
  return firstResolved(deferreds, queue: queue, cancelOthers: cancelOthers)
}

/// Return the first of an array of `Deferred`s to become resolved.
///
/// If the `Sequence` is empty, this function will return `nil`.
/// If the `Sequence`'s `Iterator` can block on `next()`, this function could block
/// while attempting to retrieve the first element.
///
/// Note that if more than one element is already resolved at the time
/// the function is called, the earliest one encountered will be considered first.
///
/// - parameter queue: the `DispatchQueue` on which the new `Deferred`'s notifications will be executed.
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get resolved first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstResolved<Success, Failure, S>(_ deferreds: S, queue: DispatchQueue,
                                               cancelOthers: Bool = false) -> Deferred<Success, Failure>?
  where S: Sequence, S.Element: Deferred<Success, Failure>
{
  guard let deferreds = NonEmptySequence(elements: deferreds) else { return nil }

  return Deferred<Success, Failure>(queue: queue) {
    first in
    // We loop over the elements on a concurrent thread
    // because nothing prevents S from blocking on `S.Iterator.next()`
    DispatchQueue.global(qos: queue.qos.qosClass).async {
      let sources: [Deferred<Success, Failure>] = deferreds.map {
        deferred in
        deferred.notify { first.resolve($0) }
        return deferred
      }

      // clean up (closure also retains sources)
      first.notify { if cancelOthers { sources.forEach { $0.cancel(.notSelected) } } }
    }
  }
}

public func firstResolved<T1, F1, T2, F2>(_ d1: Deferred<T1, F1>,
                                          _ d2: Deferred<T2, F2>,
                                          cancelOthers: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>)
{
  // find which input gets resolved first
  let selected = Deferred<ObjectIdentifier, Never>() {
    resolver in
    d1.notify { [id = ObjectIdentifier(d1)] _ in resolver.resolve(value: id) }
    d2.notify { [id = ObjectIdentifier(d2)] _ in resolver.resolve(value: id) }

    // cleanup (closure also retains sources)
    resolver.notify {
      if cancelOthers
      { // attempt to cancel the unresolved input
        d1.cancel(.notSelected)
        d2.cancel(.notSelected)
      }
    }
  }

  let o1 = select(input: d1, if: selected)
  let o2 = select(input: d2, if: selected)

  return (o1, o2)
}

public func firstResolved<T1, F1, T2, F2, T3, F3>(_ d1: Deferred<T1, F1>,
                                                  _ d2: Deferred<T2, F2>,
                                                  _ d3: Deferred<T3, F3>,
                                                  cancelOthers: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>, Deferred<T3, Error>)
{
  // find which input gets resolved first
  let selected = Deferred<ObjectIdentifier, Never>() {
    resolver in
    d1.notify { [id = ObjectIdentifier(d1)] _ in resolver.resolve(value: id) }
    d2.notify { [id = ObjectIdentifier(d2)] _ in resolver.resolve(value: id) }
    d3.notify { [id = ObjectIdentifier(d3)] _ in resolver.resolve(value: id) }

    // clean up (closure also retains sources)
    resolver.notify {
      if cancelOthers
      { // attempt to cancel the unresolved input
        d1.cancel(.notSelected)
        d2.cancel(.notSelected)
        d3.cancel(.notSelected)
      }
    }
  }

  let o1 = select(input: d1, if: selected)
  let o2 = select(input: d2, if: selected)
  let o3 = select(input: d3, if: selected)

  return (o1, o2, o3)
}

public func firstResolved<T1, F1, T2, F2, T3, F3, T4, F4>(_ d1: Deferred<T1, F1>,
                                                          _ d2: Deferred<T2, F2>,
                                                          _ d3: Deferred<T3, F3>,
                                                          _ d4: Deferred<T4, F4>,
                                                          cancelOthers: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>, Deferred<T3, Error>, Deferred<T4, Error>)
{
  // find which input gets resolved first
  let selected = Deferred<ObjectIdentifier, Never>() {
    resolver in
    d1.notify { [id = ObjectIdentifier(d1)] _ in resolver.resolve(value: id) }
    d2.notify { [id = ObjectIdentifier(d2)] _ in resolver.resolve(value: id) }
    d3.notify { [id = ObjectIdentifier(d3)] _ in resolver.resolve(value: id) }
    d4.notify { [id = ObjectIdentifier(d4)] _ in resolver.resolve(value: id) }

    // clean up (closure also retains sources)
    resolver.notify {
      if cancelOthers
      { // attempt to cancel the unresolved input
        d1.cancel(.notSelected)
        d2.cancel(.notSelected)
        d3.cancel(.notSelected)
        d4.cancel(.notSelected)
      }
    }
  }

  let o1 = select(input: d1, if: selected)
  let o2 = select(input: d2, if: selected)
  let o3 = select(input: d3, if: selected)
  let o4 = select(input: d4, if: selected)

  return (o1, o2, o3, o4)
}

private func resolveSelection<T, F>(_ queue: DispatchQueue,
                                    _ resolved: Resolver<ObjectIdentifier, Invalidation>,
                                    _ deferred: Deferred<T, F>) -> Deferred<Error, Never>
{
  return Deferred<Error, Never>(queue: queue) {
    error in
    let id = ObjectIdentifier(deferred)
    deferred.notify {
      result in
      switch result
      {
      case .success:
        resolved.resolve(value: id)
      case .failure(let e):
        error.resolve(value: e)
      }
    }
  }
}

private func select<T, F, E: Error>(input deferred: Deferred<T, F>,
                                    if selected:    Deferred<ObjectIdentifier, E>)
  -> Deferred<T, Error>
{
  return Deferred<T, Error>(queue: deferred.queue) {
    resolver in
    selected.notify {
      result in
      switch result
      {
      case .success(let id) where id != ObjectIdentifier(deferred):
        // another input of `selected` got resolved first
        resolver.cancel(.notSelected)
      default:
        resolver.resolve(deferred.result.withAnyError)
      }
    }
    resolver.retainSource(selected)
  }
}

public func firstValue<T1, F1, T2, F2>(_ d1: Deferred<T1, F1>,
                                       _ d2: Deferred<T2, F2>,
                                       cancelOthers: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>)
{
  // find which input first gets a value
  let queue = DispatchQueue(label: "select", qos: .current)
  let selected = Deferred<ObjectIdentifier, Invalidation>(queue: queue) {
    resolver in
    let errors = (
      resolveSelection(queue, resolver, d1),
      resolveSelection(queue, resolver, d2)
    )

    // figure out whether every input got an error
    let combined = combine(errors.0, errors.1)
    combined.notify { if case .success = $0 { resolver.resolve(error: .invalid("no value, only errors")) } }

    // clean up (closure also retains sources)
    resolver.notify {
      withExtendedLifetime(combined) {}
      if cancelOthers
      { // attempt to cancel the unresolved input
        d1.cancel(.notSelected)
        d2.cancel(.notSelected)
      }
    }
  }

  let o1 = select(input: d1, if: selected)
  let o2 = select(input: d2, if: selected)

  return (o1, o2)
}

public func firstValue<T1, F1, T2, F2, T3, F3>(_ d1: Deferred<T1, F1>,
                                               _ d2: Deferred<T2, F2>,
                                               _ d3: Deferred<T3, F3>,
                                               cancelOthers: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>, Deferred<T3, Error>)
{
  // find which input first gets a value
  let queue = DispatchQueue(label: "select", qos: .current)
  let selected = Deferred<ObjectIdentifier, Invalidation>() {
    resolver in
    let errors = (
      resolveSelection(queue, resolver, d1),
      resolveSelection(queue, resolver, d2),
      resolveSelection(queue, resolver, d3)
    )

    // figure out whether all inputs got errors
    let combined = combine(errors.0, errors.1, errors.2)
    combined.notify { if case .success = $0 { resolver.resolve(error: .invalid("no value, only errors")) } }

    // clean up (closure also retains sources)
    resolver.notify {
      withExtendedLifetime(combined) {}
      if cancelOthers
      { // attempt to cancel the unresolved input
        d1.cancel(.notSelected)
        d2.cancel(.notSelected)
        d3.cancel(.notSelected)
      }
    }
  }

  let o1 = select(input: d1, if: selected)
  let o2 = select(input: d2, if: selected)
  let o3 = select(input: d3, if: selected)

  return (o1, o2, o3)
}

public func firstValue<T1, F1, T2, F2, T3, F3, T4, F4>(_ d1: Deferred<T1, F1>,
                                                       _ d2: Deferred<T2, F2>,
                                                       _ d3: Deferred<T3, F3>,
                                                       _ d4: Deferred<T4, F4>,
                                                       cancelOthers: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>, Deferred<T3, Error>, Deferred<T4, Error>)
{
  // find which input first gets a value
  let queue = DispatchQueue(label: "select", qos: .current)
  let selected = Deferred<ObjectIdentifier, Invalidation>() {
    resolver in
    let errors = (
      resolveSelection(queue, resolver, d1),
      resolveSelection(queue, resolver, d2),
      resolveSelection(queue, resolver, d3),
      resolveSelection(queue, resolver, d4)
    )

    // figure out whether all inputs got errors
    let combined = combine(errors.0, errors.1, errors.2, errors.3)
    combined.notify { if case .success = $0 { resolver.resolve(error: .invalid("no value, only errors")) } }

    // clean up (closure also retains sources)
    resolver.notify {
      withExtendedLifetime(combined) {}
      if cancelOthers
      { // attempt to cancel the unresolved input
        d1.cancel(.notSelected)
        d2.cancel(.notSelected)
        d3.cancel(.notSelected)
        d4.cancel(.notSelected)
      }
    }
  }

  let o1 = select(input: d1, if: selected)
  let o2 = select(input: d2, if: selected)
  let o3 = select(input: d3, if: selected)
  let o4 = select(input: d4, if: selected)

  return (o1, o2, o3, o4)
}
