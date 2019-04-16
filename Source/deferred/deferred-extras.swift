//
//  deferred-extras.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

/*
  Definitions that rely on or extend Deferred, but do not need the fundamental, private stuff.
*/

extension Deferred
{
  // MARK: onValue: execute a task when (and only when) a computation succeeds

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes resolved with a value
  ///
  /// - parameter queue: the `DispatchQueue` on which to execute the notification; defaults to `self`'s queue.
  /// - parameter task: the closure to be enqueued
  /// - parameter value: the value of the just-resolved `Deferred`

  public func onValue(queue: DispatchQueue? = nil, task: @escaping (_ value: Value) -> Void)
  {
    notify(queue: queue, task: { $0.value.map(task) })
  }

  // MARK: onError: execute a task when (and only when) a computation fails

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes resolved with an error
  ///
  /// - parameter queue: the `DispatchQueue` on which to execute the notification; defaults to `self`'s queue.
  /// - parameter task: the closure to be enqueued
  /// - parameter error: the error from the just-resolved `Deferred`

  public func onError(queue: DispatchQueue? = nil, task: @escaping (_ error: Error) -> Void)
  {
    notify(queue: queue, task: { $0.error.map(task) })
  }
}

// MARK: enqueuing: use a different queue or QoS for notifications

extension Deferred
{
  /// Get a `Deferred` that will have the same `Result` as `self` once resolved,
  /// but will use a different queue for its notifications
  ///
  /// - parameter queue: the queue to be used by the returned `Deferred`
  /// - returns: a new `Deferred` whose notifications will execute on `queue`

  public func enqueuing(on queue: DispatchQueue) -> Deferred
  {
    if let result = self.peek()
    {
      return Deferred(queue: queue, result: result)
    }

    return TBD(queue: queue, source: self) {
      resolver in
      self.enqueue(queue: queue, boostQoS: false, task: { resolver.resolve($0) })
    }
  }

  /// Get a `Deferred` that will have the same `Result` as `self` once resolved,
  /// but will use a different queue at the specified QoS for its notifications
  ///
  /// - parameter qos: the QoS to be used by the returned `Deferred`
  /// - parameter serially: whether the notifications should be dispatched on a serial queue; defaults to `true`
  /// - returns: a new `Deferred` whose notifications will execute at QoS `qos`

  public func enqueuing(at qos: DispatchQoS, serially: Bool = true) -> Deferred
  {
    let queue = DispatchQueue(label: "deferred", qos: qos, attributes: serially ? [] : .concurrent)
    return enqueuing(on: queue)
  }
}

// MARK: map: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved, creating a new `Deferred`
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public func map<Other>(queue: DispatchQueue? = nil,
                         transform: @escaping (_ value: Value) throws -> Other) -> Deferred<Other>
  {
    return TBD(queue: queue ?? self.queue, source: self) {
      resolver in
      self.enqueue(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        resolver.beginExecution()
        do {
          let value = try result.get()
          let transformed = try transform(value)
          resolver.resolve(value: transformed)
        }
        catch {
          resolver.resolve(error: error)
        }
      }
    }
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved, creating a new `Deferred`
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public func map<Other>(qos: DispatchQoS,
                         transform: @escaping (_ value: Value) throws -> Other) -> Deferred<Other>
  {
    let queue = DispatchQueue(label: "deferred-map", qos: qos)
    return map(queue: queue, transform: transform)
  }
}

// MARK: flatMap: asynchronously transform a `Deferred` into another

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved.
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public func flatMap<Other>(queue: DispatchQueue? = nil,
                             transform: @escaping (_ value: Value) throws -> Deferred<Other>) -> Deferred<Other>
  {
    return TBD(queue: queue ?? self.queue, source: self) {
      resolver in
      self.enqueue(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        resolver.beginExecution()
        do {
          let value = try result.get()
          let transformed = try transform(value)
          transformed.enqueue(queue: queue) { resolver.resolve($0) }
          // ensure `transformed` lives as long as it needs to
          resolver.notify { _ in withExtendedLifetime(transformed){} }
        }
        catch {
          resolver.resolve(error: error)
        }
      }
    }
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved.
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public func flatMap<Other>(qos: DispatchQoS,
                             transform: @escaping (_ value: Value) throws -> Deferred<Other>) -> Deferred<Other>
  {
    let queue = DispatchQueue(label: "deferred-flatmap", qos: qos)
    return flatMap(queue: queue, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously if and when `self` becomes resolved with an error.
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter error: the Error to be transformed for a new `Deferred`

  public func recover(queue: DispatchQueue? = nil,
                      transform: @escaping (_ error: Error) throws -> Deferred<Value>) -> Deferred<Value>
  {
    return TBD(queue: queue ?? self.queue, source: self) {
      resolver in
      self.enqueue(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        resolver.beginExecution()
        if let error = result.error
        {
          do {
            let transformed = try transform(error)
            transformed.enqueue(queue: queue) { resolver.resolve($0) }
            // ensure `transformed` lives as long as it needs to
            resolver.notify { _ in withExtendedLifetime(transformed){} }
          }
          catch {
            resolver.resolve(error: error)
          }
        }
        else
        {
          resolver.resolve(result)
        }
      }
    }
  }

  /// Enqueue a transform to be computed asynchronously if and when `self` becomes resolved with an error.
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter error: the Error to be transformed for a new `Deferred`

  public func recover(qos: DispatchQoS,
                      transform: @escaping (_ error: Error) throws -> Deferred<Value>) -> Deferred<Value>
  {
    let queue = DispatchQueue(label: "deferred-recover", qos: qos)
    return recover(queue: queue, transform: transform)
  }
}

extension Deferred
{
  /// Flatten a `Deferred<Deferred<Value>>` to a `Deferred<Value>`
  ///
  /// In the right conditions, acts like a fast path for a flatMap with no transform.
  ///
  /// - parameter queue: the `DispatchQueue` onto which the new `Deferred` should dispatch notifications; use `self.queue` if `nil`
  /// - returns: a flattened `Deferred`

  public func flatten<Other>(queue: DispatchQueue? = nil) -> Deferred<Other>
    where Value == Deferred<Other>
  {
    if let result = self.peek()
    {
      do {
        let deferred = try result.get()
        if let result = deferred.peek()
        {
          return Deferred<Other>(queue: queue ?? self.queue, result: result)
        }
        else
        {
          return TBD(queue: queue ?? self.queue, source: deferred) {
            resolver in
            deferred.enqueue(queue: queue) { resolver.resolve($0) }
          }
        }
      }
      catch {
        return Deferred<Other>(queue: queue ?? self.queue, error: error)
      }
    }

    return TBD(queue: queue ?? self.queue, source: self) {
      resolver in
      self.enqueue(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        do {
          let deferred = try result.get()
          if let result = deferred.peek()
          {
            resolver.resolve(result)
          }
          else
          {
            deferred.enqueue(queue: queue) { resolver.resolve($0) }
            // ensure `deferred` lives as long as it needs to
            resolver.notify { _ in withExtendedLifetime(deferred){} }
          }
        }
        catch {
          resolver.resolve(error: error)
        }
      }
    }
  }
}

extension Deferred
{
  /// Initialize a `Deferred` with a computation task to be performed in the background
  ///
  /// If at first it does not succeed, it will try `attempts` times in total before being resolved with an `Error`.
  ///
  /// - parameter attempts: a maximum number of times to attempt `task`
  /// - parameter qos: the QoS at which the computation (and notifications) should be performed; defaults to the current QoS class.
  /// - parameter task: the computation to be performed

  public static func RetryTask(_ attempts: Int, qos: DispatchQoS = .current,
                               task: @escaping () throws -> Value) -> Deferred
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    return Deferred.RetryTask(attempts, queue: queue, task: task)
  }

  /// Initialize a `Deferred` with a computation task to be performed in the background
  ///
  /// If at first it does not succeed, it will try `attempts` times in total before being resolved with an `Error`.
  ///
  /// - parameter attempts: a maximum number of times to attempt `task`
  /// - parameter queue: the `DispatchQueue` on which the computation (and notifications) will be executed
  /// - parameter task: the computation to be performed

  public static func RetryTask(_ attempts: Int, queue: DispatchQueue,
                               task: @escaping () throws -> Value) -> Deferred
  {
    return Deferred.Retrying(attempts, queue: queue, task: { Deferred(queue: queue, task: task) })
  }

  /// Initialize a `Deferred` with a computation task to be performed in the background
  ///
  /// If at first it does not succeed, it will try `attempts` times in total before being resolved with an `Error`.
  ///
  /// - parameter attempts: a maximum number of times to attempt `task`
  /// - parameter qos: the QoS at which the computation (and notifications) should be performed; defaults to the current QoS class.
  /// - parameter task: the computation to be performed

  public static func Retrying(_ attempts: Int, qos: DispatchQoS = .current,
                              task: @escaping () throws -> Deferred) -> Deferred
  {
    guard attempts > 0 else
    {
      let error = DeferredError.invalid("task was not allowed a single attempt in \(#function)")
      return Deferred<Value>(qos: qos, error: error)
    }

    let deferred = Deferred<Deferred>(qos: qos, task: task).flatten()
    return Deferred.Retrying(attempts-1, deferred, task: task)
  }

  /// Initialize a `Deferred` with a computation task to be performed in the background
  ///
  /// If at first it does not succeed, it will try `attempts` times in total before being resolved with an `Error`.
  ///
  /// - parameter attempts: a maximum number of times to attempt `task`
  /// - parameter queue: the `DispatchQueue` on which the computation (and notifications) will be executed
  /// - parameter task: the computation to be performed

  public static func Retrying(_ attempts: Int, queue: DispatchQueue,
                              task: @escaping () throws -> Deferred) -> Deferred
  {
    guard attempts > 0 else
    {
      let error = DeferredError.invalid("task was not allowed a single attempt in \(#function)")
      return Deferred<Value>(queue: queue, error: error)
    }

    let deferred = Deferred<Deferred>(queue: queue, task: task).flatten()
    return Deferred.Retrying(attempts-1, deferred, task: task)
  }

  private static func Retrying(_ attempts: Int, _ deferred: Deferred, task: @escaping () throws -> Deferred) -> Deferred
  {
    return (0..<attempts).reduce(deferred) {
      (deferred, _) in
      deferred.recover(transform: { _ in try task() })
    }
  }
}

// MARK: apply: modify this `Deferred`'s value using a `Deferred` transform

extension Deferred
{
  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become resolved.
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public func apply<Other>(queue: DispatchQueue? = nil,
                           transform: Deferred<(_ value: Value) throws -> Other>) -> Deferred<Other>
  {
    return TBD(queue: queue ?? self.queue, source: self) {
      resolver in
      self.enqueue(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        do {
          let value = try result.get()
          transform.enqueue(queue: queue) {
            transform in
            guard resolver.needsResolution else { return }
            resolver.beginExecution()
            do {
              let transform = try transform.get()
              let transformed = try transform(value)
              resolver.resolve(value: transformed)
            }
            catch {
              resolver.resolve(error: error)
            }
          }
          // ensure `transform` lives as long as it needs to
          resolver.notify { _ in withExtendedLifetime(transform){} }
        }
        catch {
          resolver.resolve(error: error)
        }
      }
    }
  }

  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become resolved.
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public func apply<Other>(qos: DispatchQoS,
                           transform: Deferred<(_ value: Value) throws -> Other>) -> Deferred<Other>
  {
    let queue = DispatchQueue(label: "deferred-apply", qos: qos)
    return apply(queue: queue, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become resolved.
  ///
  /// Adaptor made desirable by insufficient covariance from throwing to non-throwing closure types. (radar 22013315)
  /// (i.e. if the difference between the type signature of two closures is whether they throw,
  /// the non-throwing one should be usable anywhere the throwing one can.)
  /// Can hopefully be removed later.
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public func apply<Other>(queue: DispatchQueue? = nil,
                           transform: Deferred<(_ value: Value) -> Other>) -> Deferred<Other>
  {
    let retransform = transform.map(queue: queue) { transform in { v throws in transform(v) } }
    return apply(queue: queue, transform: retransform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become resolved.
  ///
  /// Adaptor made desirable by insufficient covariance from throwing to non-throwing closure types. (radar 22013315)
  /// (i.e. if the difference between the type signature of two closures is whether they throw,
  /// the non-throwing one should be usable anywhere the throwing one can.)
  /// Can hopefully be removed later.
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public func apply<Other>(qos: DispatchQoS,
                           transform: Deferred<(_ value: Value) -> Other>) -> Deferred<Other>
  {
    let retransform = transform.map(queue: queue) { transform in { v throws in transform(v) } }
    return apply(qos: qos, transform: retransform)
  }
}

extension Deferred
{
  /// Insert a validation step in a chain of Deferred.
  ///
  /// Pass `Value` through if it passes the predicate, otherwise replace it with the error `DeferredError.invalid`.
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter predicate: a predicate that validates the passed-in `Value` by returning a Boolean
  /// - parameter message: an explanation to add to `DeferredError.invalid`; defaults to the empty `String`
  /// - returns: a `Deferred` reference holding a validated `Value`
  /// - parameter value: the value to be validated

  public func validate(queue: DispatchQueue? = nil,
                       predicate: @escaping (_ value: Value) -> Bool, message: String = "") -> Deferred
  {
    return self.map(queue: queue) {
      value in
      guard predicate(value) else { throw DeferredError.invalid(message) }
      return value
    }
  }

  /// Insert a validation step in a chain of Deferred.
  ///
  /// Pass `Value` through if it passes the predicate, otherwise replace it with the error `DeferredError.invalid`.
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter predicate: a predicate that validates the passed-in `Value` by returning a Boolean
  /// - parameter message: an explanation to add to `DeferredError.invalid`; defaults to the empty `String`
  /// - returns: a `Deferred` reference holding a validated `Value`
  /// - parameter value: the value to be validated

  public func validate(qos: DispatchQoS,
                       predicate: @escaping (_ value: Value) -> Bool, message: String = "") -> Deferred
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    return validate(queue: queue, predicate: predicate, message: message)
  }

  /// Insert a validation step in a chain of Deferred.
  ///
  /// Pass `Value` through if the predicate returns normally, otherwise replace it by the `Error` thrown by the predicate.
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter predicate: a closure that validates the passed-in `Value` by either returning normally or throwing
  /// - returns: a `Deferred` reference holding a validated `Value`
  /// - parameter value: the value to be validated

  public func validate(queue: DispatchQueue? = nil,
                       predicate: @escaping (_ value: Value) throws -> Void) -> Deferred
  {
    return self.map(queue: queue) {
      value in
      try predicate(value)
      return value
    }
  }

  /// Insert a validation step in a chain of Deferred.
  ///
  /// Pass `Value` through if the predicate returns normally, otherwise replace it by the `Error` thrown by the predicate.
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter predicate: a closure that validates the passed-in `Value` by either returning normally or throwing
  /// - returns: a `Deferred` reference holding a validated `Value`
  /// - parameter value: the value to be validated

  public func validate(qos: DispatchQoS,
                       predicate: @escaping (_ value: Value) throws -> Void) -> Deferred
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    return validate(queue: queue, predicate: predicate)
  }
}

extension Optional
{
  /// Create a `Deferred` from this `Optional`.
  ///
  /// If `optional` is `nil` then `Deferred` will be resolved with the error `DeferredError.invalid`
  ///
  /// - parameter queue: the dispatch queue upon the new `Deferred`'s notifications will be performed

  public func deferred(queue: DispatchQueue) -> Deferred<Wrapped>
  {
    switch self
    {
    case .some(let value):
      return Deferred(queue: queue, value: value)
    case .none:
      return Deferred(queue: queue, error: DeferredError.invalid("initialized from a nil Optional"))
    }
  }

  /// Create a `Deferred` from this `Optional`.
  ///
  /// If `optional` is `nil` then `Deferred` will be resolved with the error `DeferredError.invalid`
  ///
  /// - parameter qos: the QoS at which to perform notifications for the new `Deferred`; defaults to the current QoS class.

  public func deferred(qos: DispatchQoS = .current) -> Deferred<Wrapped>
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    return self.deferred(queue: queue)
  }
}
