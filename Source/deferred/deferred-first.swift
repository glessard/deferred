//
//  deferred-first.swift
//  deferred
//
//  Created by Guillaume Lessard on 10/9/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import Dispatch

/// Return the value of the first of an array of `Deferred`s to be determined.
/// Note that if the array is empty the resulting `Deferred` will resolve to a
/// `DeferredError.canceled` error.
/// Note also that if more than one element is already determined at the time
/// the function is called, the earliest one will be considered first; if this
/// biasing is a problem, consider shuffling the collection first.
///
/// - parameter qos: the QoS at which to execute the new `Deferred`'s notifications; defaults to the current QoS class.
/// - parameter deferreds: a `Collection` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Value, C: Collection>(qos: DispatchQoS,
                                             deferreds: C, cancelOthers: Bool = false) -> Deferred<Value>
  where C.Iterator.Element: Deferred<Value>
{
  return Flatten(firstDetermined(qos: qos, deferreds: deferreds, cancelOthers: cancelOthers))
}

public func firstValue<Value, C: Collection>(_ deferreds: C, cancelOthers: Bool = false) -> Deferred<Value>
  where C.Iterator.Element: Deferred<Value>
{
  return firstValue(qos: .current, deferreds: deferreds, cancelOthers: cancelOthers)
}

public func firstValue<Value, C: Collection>(queue: DispatchQueue,
                                             deferreds: C, cancelOthers: Bool = false) -> Deferred<Value>
  where C.Iterator.Element: Deferred<Value>
{
  return Flatten(firstDetermined(queue: queue, deferreds: deferreds, cancelOthers: cancelOthers))
}

/// Return the value of the first of an array of `Deferred`s to be determined.
/// Note that if the array is empty the resulting `Deferred` will resolve to a
/// `DeferredError.canceled` error.
/// Note also that if more than one element is already determined at the time
/// the function is called, the earliest one will be considered first.
///
/// - parameter qos: the QoS at which to execute the new `Deferred`'s notifications; defaults to the current QoS class.
/// - parameter deferreds: a `Sequence` of `Deferred`
/// - parameter cancelOthers: whether to attempt to cancel every `Deferred` that doesn't get determined first (defaults to `false`)
/// - returns: a new `Deferred`

public func firstValue<Value, S: Sequence>(qos: DispatchQoS,
                                           deferreds: S, cancelOthers: Bool = false) -> Deferred<Value>
  where S.Iterator.Element: Deferred<Value>
{
  return Flatten(firstDetermined(qos: qos, deferreds: deferreds, cancelOthers: cancelOthers))
}

public func firstValue<Value, S: Sequence>(_ deferreds: S, cancelOthers: Bool = false) -> Deferred<Value>
  where S.Iterator.Element: Deferred<Value>
{
  return firstValue(qos: .current, deferreds: deferreds, cancelOthers: cancelOthers)
}

public func firstValue<Value, S: Sequence>(queue: DispatchQueue,
                                           deferreds: S, cancelOthers: Bool = false) -> Deferred<Value>
  where S.Iterator.Element: Deferred<Value>
{
  return Flatten(firstDetermined(queue: queue, deferreds: deferreds, cancelOthers: cancelOthers))
}

/// Return the first of an array of `Deferred`s to become determined.
/// Note that if the array is empty the resulting `Deferred` will resolve to a
/// `DeferredError.canceled` error.
/// Note also that if more than one element is already determined at the time
/// the function is called, the earliest one will be considered first; if this
/// biasing is a problem, consider shuffling the collection first.
///
/// - parameter qos: the QoS at which to execute the new `Deferred`'s notifications; defaults to the current QoS class.
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

public func firstDetermined<Value, C: Collection>(_ deferreds: C, cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
  where C.Iterator.Element: Deferred<Value>
{
  return firstDetermined(qos: .current, deferreds: deferreds, cancelOthers: cancelOthers)
}

public func firstDetermined<Value, C: Collection>(queue: DispatchQueue,
                                                  deferreds: C, cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
  where C.Iterator.Element: Deferred<Value>
{
  if deferreds.count == 0
  {
    let error = DeferredError.invalid("cannot find first determined from an empty set in \(#function)")
    return Deferred(queue: queue, error: error)
  }

  let first = TBD<Deferred<Value>>(queue: queue)

  deferreds.forEach {
    deferred in
    deferred.notify { _ in first.determine(deferred) }
    if cancelOthers { first.notify { _ in deferred.cancel() } }
  }

  return first
}

/// Return the first of an array of `Deferred`s to become determined.
/// Note that if the array is empty the resulting `Deferred` will resolve to a
/// `DeferredError.canceled` error.
/// Note also that if more than one element is already determined at the time
/// the function is called, the earliest one will be considered first.
///
/// - parameter qos: the QoS at which to execute the new `Deferred`'s notifications; defaults to the current QoS class.
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

public func firstDetermined<Value, S: Sequence>(_ deferreds: S, cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
where S.Iterator.Element: Deferred<Value>
{
  return firstDetermined(qos: .current, deferreds: deferreds, cancelOthers: cancelOthers)
}

public func firstDetermined<Value, S: Sequence>(queue: DispatchQueue,
                                                deferreds: S, cancelOthers: Bool = false) -> Deferred<Deferred<Value>>
  where S.Iterator.Element: Deferred<Value>
{
  let first = TBD<Deferred<Value>>(queue: queue)

  // We execute `Sequence.forEach` on a background thread
  // because nothing prevents S from blocking on `Sequence.next()`
  queue.async {
    var subscribed = false
    deferreds.forEach {
      deferred in
      subscribed = true
      deferred.notify { _ in first.determine(deferred) }
      if cancelOthers { first.notify { _ in deferred.cancel() } }
    }

    if !subscribed
    {
      let error = DeferredError.invalid("cannot find first determined from an empty set in \(#function)")
      first.determine(error)
    }
  }

  return first
}
