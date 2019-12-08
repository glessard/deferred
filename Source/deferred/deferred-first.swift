//
//  deferred-first.swift
//  deferred
//
//  Created by Guillaume Lessard on 10/9/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import Dispatch

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
          switch cancelOthers && (Cancellation.notSelected is Failure)
          { // retain and cancel source, or just retain it
          case true: f.notify { deferred.cancel(.notSelected) }
          default:   f.retainSource(deferred)
          }
        }
        errors.append(error.execute)
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
        switch cancelOthers && (Cancellation.notSelected is Failure)
        { // retain and cancel source, or just retain it
        case true: resolver.notify { deferred.cancel(.notSelected) }
        default:   resolver.retainSource(deferred)
        }
      }
    }
  }
}

public func firstResolved<T1, F1, T2, F2>(_ d1: Deferred<T1, F1>,
                                          _ d2: Deferred<T2, F2>,
                                          canceling: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>)
{
  // find which input gets resolved first
  let selected = Deferred<ObjectIdentifier, Cancellation>() {
    resolver in
    d1.notify { [id = ObjectIdentifier(d1)] _ in resolver.resolve(value: id) }
    d2.notify { [id = ObjectIdentifier(d2)] _ in resolver.resolve(value: id) }

    // cleanup (closure also retains sources)
    resolver.notify {
      if canceling
      { // attempt to cancel the unresolved input
        d1.cancel(.notSelected)
        d2.cancel(.notSelected)
      }
    }
  }

  let o1 = select(d1, if: selected)
  let o2 = select(d2, if: selected)

  return (o1, o2)
}

public func firstResolved<T1, F1, T2, F2, T3, F3>(_ d1: Deferred<T1, F1>,
                                                  _ d2: Deferred<T2, F2>,
                                                  _ d3: Deferred<T3, F3>,
                                                  canceling: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>, Deferred<T3, Error>)
{
  // find which input gets resolved first
  let selected = Deferred<ObjectIdentifier, Cancellation>() {
    resolver in
    d1.notify { [id = ObjectIdentifier(d1)] _ in resolver.resolve(value: id) }
    d2.notify { [id = ObjectIdentifier(d2)] _ in resolver.resolve(value: id) }
    d3.notify { [id = ObjectIdentifier(d3)] _ in resolver.resolve(value: id) }

    // clean up (closure also retains sources)
    resolver.notify {
      if canceling
      { // attempt to cancel the unresolved input
        d1.cancel(.notSelected)
        d2.cancel(.notSelected)
        d3.cancel(.notSelected)
      }
    }
  }

  let o1 = select(d1, if: selected)
  let o2 = select(d2, if: selected)
  let o3 = select(d3, if: selected)

  return (o1, o2, o3)
}

public func firstResolved<T1, F1, T2, F2, T3, F3, T4, F4>(_ d1: Deferred<T1, F1>,
                                                          _ d2: Deferred<T2, F2>,
                                                          _ d3: Deferred<T3, F3>,
                                                          _ d4: Deferred<T4, F4>,
                                                          canceling: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>, Deferred<T3, Error>, Deferred<T4, Error>)
{
  // find which input gets resolved first
  let selected = Deferred<ObjectIdentifier, Cancellation>() {
    resolver in
    d1.notify { [id = ObjectIdentifier(d1)] _ in resolver.resolve(value: id) }
    d2.notify { [id = ObjectIdentifier(d2)] _ in resolver.resolve(value: id) }
    d3.notify { [id = ObjectIdentifier(d3)] _ in resolver.resolve(value: id) }
    d4.notify { [id = ObjectIdentifier(d4)] _ in resolver.resolve(value: id) }

    // clean up (closure also retains sources)
    resolver.notify {
      if canceling
      { // attempt to cancel the unresolved input
        d1.cancel(.notSelected)
        d2.cancel(.notSelected)
        d3.cancel(.notSelected)
        d4.cancel(.notSelected)
      }
    }
  }

  let o1 = select(d1, if: selected)
  let o2 = select(d2, if: selected)
  let o3 = select(d3, if: selected)
  let o4 = select(d4, if: selected)

  return (o1, o2, o3, o4)
}

private func resolveSelection<T, F>(_ queue: DispatchQueue,
                                    _ resolver: Resolver<ObjectIdentifier, Cancellation>,
                                    _ deferred: Deferred<T, F>) -> Deferred<Error, Cancellation>
{
  let notifier = Deferred<Error, Cancellation>(queue: queue) {
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
  }
  return notifier.execute
}

private func select<T, F>(_ deferred:  Deferred<T, F>,
                          if selected: Deferred<ObjectIdentifier, Cancellation>)
  -> Deferred<T, Error>
{
  return Deferred<T, Error>(queue: deferred.queue) {
    resolver in
    selected.notify {
      result in
      switch result
      {
      case .success(let id) where id == ObjectIdentifier(deferred):
        resolver.resolve(deferred.result.withAnyError)
      case .success: // another `Deferred` got resolved first
        resolver.cancel(.notSelected)
      case .failure: // all inputs got errors: transfer them to the outputs
        resolver.resolve(deferred.result.withAnyError)
      }
    }
    resolver.retainSource(selected)
  }
}

public func firstValue<T1, F1, T2, F2>(_ d1: Deferred<T1, F1>,
                                       _ d2: Deferred<T2, F2>,
                                       canceling: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>)
{
  // find which input first gets a value
  let queue = DispatchQueue(label: "select", qos: .current)
  let selected = Deferred<ObjectIdentifier, Cancellation>(queue: queue) {
    resolver in
    let errors = [
      resolveSelection(queue, resolver, d1),
      resolveSelection(queue, resolver, d2),
    ]

    // figure out whether every input got an error
    let combined = combine(queue: queue, deferreds: errors)
    combined.notify { if case .success = $0 { resolver.resolve(error: .notSelected) } }

    // clean up (closure also retains sources)
    resolver.notify {
      combined.cancel()
      if canceling
      { // attempt to cancel the unresolved input
        d1.cancel(.notSelected)
        d2.cancel(.notSelected)
      }
    }
  }

  let o1 = select(d1, if: selected)
  let o2 = select(d2, if: selected)

  return (o1, o2)
}

public func firstValue<T1, F1, T2, F2, T3, F3>(_ d1: Deferred<T1, F1>,
                                               _ d2: Deferred<T2, F2>,
                                               _ d3: Deferred<T3, F3>,
                                               canceling: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>, Deferred<T3, Error>)
{
  // find which input first gets a value
  let queue = DispatchQueue(label: "select", qos: .current)
  let selected = Deferred<ObjectIdentifier, Cancellation>() {
    resolver in
    let errors = [
      resolveSelection(queue, resolver, d1),
      resolveSelection(queue, resolver, d2),
      resolveSelection(queue, resolver, d3),
    ]

    // figure out whether all inputs got errors
    let combined = combine(queue: queue, deferreds: errors)
    combined.notify { if case .success = $0 { resolver.resolve(error: .notSelected) } }

    // clean up (closure also retains sources)
    resolver.notify {
      combined.cancel()
      if canceling
      { // attempt to cancel the unresolved input
        d1.cancel(.notSelected)
        d2.cancel(.notSelected)
        d3.cancel(.notSelected)
      }
    }
  }

  let o1 = select(d1, if: selected)
  let o2 = select(d2, if: selected)
  let o3 = select(d3, if: selected)

  return (o1, o2, o3)
}

public func firstValue<T1, F1, T2, F2, T3, F3, T4, F4>(_ d1: Deferred<T1, F1>,
                                                       _ d2: Deferred<T2, F2>,
                                                       _ d3: Deferred<T3, F3>,
                                                       _ d4: Deferred<T4, F4>,
                                                       canceling: Bool = false)
  -> (Deferred<T1, Error>, Deferred<T2, Error>, Deferred<T3, Error>, Deferred<T4, Error>)
{
  // find which input first gets a value
  let queue = DispatchQueue(label: "select", qos: .current)
  let selected = Deferred<ObjectIdentifier, Cancellation>() {
    resolver in
    let errors = [
      resolveSelection(queue, resolver, d1),
      resolveSelection(queue, resolver, d2),
      resolveSelection(queue, resolver, d3),
      resolveSelection(queue, resolver, d4),
    ]

    // figure out whether all inputs got errors
    let combined = combine(queue: queue, deferreds: errors)
    combined.notify { if case .success = $0 { resolver.resolve(error: .notSelected) } }

    // clean up (closure also retains sources)
    resolver.notify {
      combined.cancel()
      if canceling
      { // attempt to cancel the unresolved input
        d1.cancel(.notSelected)
        d2.cancel(.notSelected)
        d3.cancel(.notSelected)
        d4.cancel(.notSelected)
      }
    }
  }

  let o1 = select(d1, if: selected)
  let o2 = select(d2, if: selected)
  let o3 = select(d3, if: selected)
  let o4 = select(d4, if: selected)

  return (o1, o2, o3, o4)
}
