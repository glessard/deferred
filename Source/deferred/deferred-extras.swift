//
//  deferred-extras.swift
//  deferred
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
  // MARK: notify: execute a task when this `deferred` becomes resolved

  /// Enqueue a notification to be performed asynchronously after this `Deferred` becomes resolved.
  ///
  /// This function will extend the lifetime of this `Deferred` until `task` completes.
  ///
  /// - parameter queue: the `DispatchQueue` on which to dispatch this notification when ready; defaults to `self`'s queue.
  /// - parameter task: a closure to be executed as a notification
  /// - parameter result: the `Result` of this `Deferred`

  public func onResult(queue: DispatchQueue? = nil, task: @escaping (_ result: Result<Success, Failure>) -> Void)
  {
    notify(queue: queue, handler: { result in withExtendedLifetime(self, { task(result) }) })
  }

  // MARK: onValue: execute a task when (and only when) a computation succeeds

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes resolved with a value
  ///
  /// This function will extend the lifetime of this `Deferred` until `task` completes.
  ///
  /// - parameter queue: the `DispatchQueue` on which to execute the notification; defaults to `self`'s queue.
  /// - parameter task: the closure to be enqueued
  /// - parameter value: the value of the just-resolved `Deferred`

  public func onValue(queue: DispatchQueue? = nil, task: @escaping (_ value: Success) -> Void)
  {
    onResult(queue: queue, task: { $0.value.map(task) })
  }

  // MARK: onError: execute a task when (and only when) a computation fails

  /// Enqueue a closure to be performed asynchronously, if and only if after `self` becomes resolved with an error
  ///
  /// This function will extend the lifetime of this `Deferred` until `task` completes.
  ///
  /// - parameter queue: the `DispatchQueue` on which to execute the notification; defaults to `self`'s queue.
  /// - parameter task: the closure to be enqueued
  /// - parameter error: the error from the just-resolved `Deferred`

  public func onError(queue: DispatchQueue? = nil, task: @escaping (_ error: Failure) -> Void)
  {
    onResult(queue: queue, task: { $0.error.map(task) })
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

    return Deferred(queue: queue) {
      resolver in
      self.notify(queue: queue, boostQoS: false, handler: { resolver.resolve($0) })
      resolver.retainSource(self)
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
  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved succesfully, creating a new `Deferred`
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for the new `Deferred`

  public func map<Other>(queue: DispatchQueue? = nil,
                         transform: @escaping (_ value: Success) -> Other) -> Deferred<Other, Failure>
  {
    return Deferred<Other, Failure>(queue: queue ?? self.queue) {
      resolver in
      self.notify(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        resolver.resolve(result.map(transform))
      }
      resolver.retainSource(self)
    }
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved succesfully, creating a new `Deferred`
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for the new `Deferred`

  public func map<Other>(qos: DispatchQoS,
                         transform: @escaping (_ value: Success) -> Other) -> Deferred<Other, Failure>
  {
    let queue = DispatchQueue(label: "deferred-map", qos: qos)
    return map(queue: queue, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved succesfully, creating a new `Deferred`
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter transform: the throwing transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for the new `Deferred`

  public func tryMap<Other>(queue: DispatchQueue? = nil,
                            transform: @escaping (_ value: Success) throws -> Other) -> Deferred<Other, Error>
  {
    return Deferred<Other, Error>(queue: queue ?? self.queue) {
      resolver in
      self.notify(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        resolver.resolve(Result(catching: { try transform(result.get()) }))
      }
      resolver.retainSource(self)
    }
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved succesfully, creating a new `Deferred`
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the throwing transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for the new `Deferred`

  public func tryMap<Other>(qos: DispatchQoS,
                            transform: @escaping (_ value: Success) throws -> Other) -> Deferred<Other, Error>
  {
    let queue = DispatchQueue(label: "deferred-trymap", qos: qos)
    return tryMap(queue: queue, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved with a `Failure`, creating a new `Deferred`
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter error: the `Failure` to be transformed for the new `Deferred`

  public func mapError<OtherFailure>(queue: DispatchQueue? = nil,
                                     transform: @escaping (_ error: Failure) -> OtherFailure) -> Deferred<Success, OtherFailure>
  {
    return Deferred<Success, OtherFailure>(queue: queue ?? self.queue) {
      resolver in
      self.notify(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        resolver.resolve(result.mapError(transform))
      }
      resolver.retainSource(self)
    }
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved with a `Failure`, creating a new `Deferred`
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter error: the `Failure` to be transformed for the new `Deferred`

  public func mapError<OtherFailure>(qos: DispatchQoS,
                                     transform: @escaping (_ error: Failure) -> OtherFailure) -> Deferred<Success, OtherFailure>
  {
    let queue = DispatchQueue(label: "deferred-maperror", qos: qos)
    return mapError(queue: queue, transform: transform)
  }

  /// Map this `Deferred`'s `Failure` type to `Error` (any Error).
  ///
  /// returns: a `Deferred` where the `Failure` type is unconditionally converted to `Error`

  public var withAnyError: Deferred<Success, Error> {
    return Deferred<Success, Error>(queue: queue) {
      resolver in
      self.notify(queue: nil) {
        result in
        resolver.resolve(result.withAnyError)
      }
      resolver.retainSource(self)
    }
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
  /// - parameter value: the value to be transformed for the new `Deferred`

  public func flatMap<Other>(queue: DispatchQueue? = nil,
                             transform: @escaping(_ value: Success) -> Deferred<Other, Failure>) -> Deferred<Other, Failure>
  {
    return Deferred<Other, Failure>(queue: queue ?? self.queue) {
      resolver in
      self.notify(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        switch result
        {
        case .success(let value):
          let transformed = transform(value)
          if let transformed = transformed.peek()
          {
            resolver.resolve(transformed)
          }
          else
          {
            transformed.notify(queue: queue) { resolver.resolve($0) }
            resolver.retainSource(transformed)
          }
        case .failure(let error):
          resolver.resolve(error: error)
        }
      }
      resolver.retainSource(self)
    }
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved.
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for the new `Deferred`

  public func flatMap<Other>(qos: DispatchQoS,
                             transform: @escaping (_ value: Success) -> Deferred<Other, Failure>) -> Deferred<Other, Failure>
  {
    let queue = DispatchQueue(label: "deferred-flatmap", qos: qos)
    return flatMap(queue: queue, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved.
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for the new `Deferred`

  public func tryFlatMap<Other>(queue: DispatchQueue? = nil,
                                transform: @escaping (_ value: Success) throws -> Deferred<Other, Error>) -> Deferred<Other, Error>
  {
    return Deferred<Other, Error>(queue: queue ?? self.queue) {
      resolver in
      self.notify(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        do {
          let value = try result.get()
          let transformed = try transform(value)
          if let transformed = transformed.peek()
          {
            resolver.resolve(transformed)
          }
          else
          {
            transformed.notify(queue: queue) { resolver.resolve($0) }
            resolver.retainSource(transformed)
          }
        }
        catch {
          resolver.resolve(error: error)
        }
      }
      resolver.retainSource(self)
    }
  }

  /// Enqueue a transform to be computed asynchronously after `self` becomes resolved.
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for the new `Deferred`

  public func tryFlatMap<Other>(qos: DispatchQoS,
                                transform: @escaping (_ value: Success) throws -> Deferred<Other, Error>) -> Deferred<Other, Error>
  {
    let queue = DispatchQueue(label: "deferred-flatmap", qos: qos)
    return tryFlatMap(queue: queue, transform: transform)
  }

  /// Enqueue a transform to be computed asynchronously if and when `self` becomes resolved with an error.
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter error: the Error to be transformed for the new `Deferred`

  public func flatMapError<OtherFailure>(queue: DispatchQueue? = nil,
                                         transform: @escaping (_ error: Failure) -> Deferred<Success, OtherFailure>) -> Deferred<Success, OtherFailure>
  {
    return Deferred<Success, OtherFailure>(queue: queue ?? self.queue) {
      resolver in
      self.notify(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        switch result
        {
        case let .success(value):
          resolver.resolve(value: value)

        case let .failure(error):
          let transformed = transform(error)
          if let transformed = transformed.peek()
          {
            resolver.resolve(transformed)
          }
          else
          {
            transformed.notify(queue: queue) { resolver.resolve($0) }
            resolver.retainSource(transformed)
          }
        }
      }
      resolver.retainSource(self)
    }
  }

  /// Enqueue a transform to be computed asynchronously if and when `self` becomes resolved with an error.
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter error: the Error to be transformed for the new `Deferred`

  public func flatMapError<OtherFailure>(qos: DispatchQoS,
                                         transform: @escaping(_ error: Failure) -> Deferred<Success, OtherFailure>) -> Deferred<Success, OtherFailure>
  {
    let queue = DispatchQueue(label: "deferred-flatmaperror", qos: qos)
    return flatMapError(queue: queue, transform: transform)
  }
}

extension Deferred
{
  /// Flatten a `Deferred<Deferred<Success>, Failure>` to a `Deferred<Success, Failure>`
  ///
  /// In the right conditions, acts like a fast path for a flatMap with no transform.
  ///
  /// - parameter queue: the `DispatchQueue` onto which the new `Deferred` should
  ///                    dispatch notifications; use `self.queue` if `nil`
  /// - returns: a flattened `Deferred`

  public func flatten<Other>(queue: DispatchQueue? = nil) -> Deferred<Other, Failure>
    where Success == Deferred<Other, Failure>
  {
    if let result = self.peek()
    {
      switch result
      {
      case .success(let deferred):
        if let result = deferred.peek()
        {
          return Deferred<Other, Failure>(queue: queue ?? self.queue, result: result)
        }

        return Deferred<Other, Failure>(queue: queue ?? self.queue) {
          resolver in
          deferred.notify(queue: queue) { resolver.resolve($0) }
          resolver.retainSource(deferred)
        }

      case .failure(let error):
        return Deferred<Other, Failure>(queue: queue ?? self.queue, error: error)
      }
    }

    return Deferred<Other, Failure>(queue: queue ?? self.queue) {
      resolver in
      self.notify(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        switch result
        {
        case .success(let deferred):
          if let result = deferred.peek()
          {
            resolver.resolve(result)
          }
          else
          {
            deferred.notify(queue: queue) { resolver.resolve($0) }
            resolver.retainSource(deferred)
          }
        case .failure(let error):
          resolver.resolve(error: error)
        }
      }
      resolver.retainSource(self)
    }
  }

  /// Flatten a `Deferred<Deferred<Success>, Never>` to a `Deferred<Success, Failure>`
  ///
  /// In the right conditions, acts like a fast path for a flatMap with no transform.
  ///
  /// - parameter queue: the `DispatchQueue` onto which the new `Deferred` should
  ///                    dispatch notifications; use `self.queue` if `nil`
  /// - returns: a flattened `Deferred`

  public func flatten<Other, OtherFailure>(queue: DispatchQueue? = nil) -> Deferred<Other, OtherFailure>
    where Success == Deferred<Other, OtherFailure>, Failure == Never
  {
    if let result = self.peek()
    {
      switch result
      {
      case .success(let deferred):
        if let result = deferred.peek()
        {
          return Deferred<Other, OtherFailure>(queue: queue ?? self.queue, result: result)
        }

        return Deferred<Other, OtherFailure>(queue: queue ?? self.queue) {
          resolver in
          deferred.notify(queue: queue) { resolver.resolve($0) }
          resolver.retainSource(deferred)
        }
      }
    }

    return Deferred<Other, OtherFailure>(queue: queue ?? self.queue) {
      resolver in
      self.notify(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        switch result
        {
        case .success(let deferred):
          if let result = deferred.peek()
          {
            resolver.resolve(result)
          }
          else
          {
            deferred.notify(queue: queue) { resolver.resolve($0) }
            resolver.retainSource(deferred)
          }
        }
      }
      resolver.retainSource(self)
    }
  }

}

extension Deferred where Failure == Error
{
  /// Enqueue a transform to be computed asynchronously if and when `self` becomes resolved with an error.
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter error: the Error to be transformed for the new `Deferred`

  public func recover(queue: DispatchQueue? = nil,
                      transform: @escaping (_ error: Error) throws -> Deferred) -> Deferred
  {
    return Deferred(queue: queue ?? self.queue) {
      resolver in
      self.notify(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        switch result
        {
        case let .success(value):
          resolver.resolve(value: value)

        case let .failure(error):
          do {
            let transformed = try transform(error)
            if let transformed = transformed.peek()
            {
              resolver.resolve(transformed)
            }
            else
            {
              transformed.notify(queue: queue) { resolver.resolve($0) }
              resolver.retainSource(transformed)
            }
          }
          catch {
            resolver.resolve(error: error)
          }
        }
      }
      resolver.retainSource(self)
    }
  }

  /// Enqueue a transform to be computed asynchronously if and when `self` becomes resolved with an error.
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the transform to be performed
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter error: the Error to be transformed for the new `Deferred`

  public func recover(qos: DispatchQoS,
                      transform: @escaping (_ error: Error) throws -> Deferred) -> Deferred
  {
    let queue = DispatchQueue(label: "deferred-recover", qos: qos)
    return recover(queue: queue, transform: transform)
  }

  /// Initialize a `Deferred` with a computation task to be performed in the background
  ///
  /// If at first it does not succeed, it will try `attempts` times in total before being resolved with an `Error`.
  ///
  /// - parameter attempts: a maximum number of times to attempt `task`
  /// - parameter qos: the QoS at which the computation (and notifications) should be performed; defaults to the current QoS class.
  /// - parameter task: the computation to be performed

  public static func RetryTask(_ attempts: Int, qos: DispatchQoS = .current,
                               task: @escaping () throws -> Success) -> Deferred
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
                               task: @escaping () throws -> Success) -> Deferred
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
    let queue = DispatchQueue(label: "retrying", qos: qos)
    return Deferred.Retrying(attempts, queue: queue, task: task)
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
    let error = Invalidation.invalid("task was not allowed a single attempt in \(#function)")
    let deferred = Deferred(queue: queue, error: error)

    if attempts < 1 { return deferred }

    return Deferred.Retrying(attempts, deferred, task: task)
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
                           transform: Deferred<(_ value: Success) -> Other, Never>) -> Deferred<Other, Failure>
  {
    func applyTransform(_ value: Success,
                        _ transform: Result<(Success) -> Other, Never>,
                        _ resolver: Resolver<Other, Failure>)
    {
      switch transform
      {
      case .success(let transform):
        resolver.resolve(value: transform(value))
      }
    }

    return Deferred<Other, Failure>(queue: queue ?? self.queue) {
      resolver in
      self.notify(queue: queue) {
        result in
        guard resolver.needsResolution else { return }
        switch result
        {
        case .success(let value):
          if let transform = transform.peek()
          {
            applyTransform(value, transform, resolver)
          }
          else
          {
            transform.notify(queue: queue) {
              transform in
              guard resolver.needsResolution else { return }
              applyTransform(value, transform, resolver)
            }
            resolver.retainSource(transform)
          }

        case .failure(let error):
          resolver.resolve(error: error)
        }
      }
      resolver.retainSource(self)
    }
  }

  /// Enqueue a transform to be computed asynchronously after `self` and `transform` become resolved.
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter transform: the transform to be performed, wrapped in a `Deferred`
  /// - returns: a `Deferred` reference representing the return value of the transform
  /// - parameter value: the value to be transformed for a new `Deferred`

  public func apply<Other>(qos: DispatchQoS,
                           transform: Deferred<(_ value: Success) -> Other, Never>) -> Deferred<Other, Failure>
  {
    let queue = DispatchQueue(label: "deferred-apply", qos: qos)
    return apply(queue: queue, transform: transform)
  }
}

extension Deferred
{
  /// Insert a validation step in a chain of Deferred.
  ///
  /// Pass `Success` through if it passes the predicate, otherwise replace it with the error `DeferredError.invalid`.
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter predicate: a predicate that validates the passed-in `Success` by returning a Boolean
  /// - parameter message: an explanation to add to `DeferredError.invalid`; defaults to the empty `String`
  /// - returns: a `Deferred` reference holding a validated `Success`
  /// - parameter value: the value to be validated

  public func validate(queue: DispatchQueue? = nil,
                       predicate: @escaping (_ value: Success) -> Bool, message: String = "") -> Deferred<Success, Error>
  {
    return self.tryMap(queue: queue) {
      value in
      guard predicate(value) else { throw Invalidation.invalid(message) }
      return value
    }
  }

  /// Insert a validation step in a chain of Deferred.
  ///
  /// Pass `Success` through if it passes the predicate, otherwise replace it with the error `DeferredError.invalid`.
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter predicate: a predicate that validates the passed-in `Success` by returning a Boolean
  /// - parameter message: an explanation to add to `DeferredError.invalid`; defaults to the empty `String`
  /// - returns: a `Deferred` reference holding a validated `Success`
  /// - parameter value: the value to be validated

  public func validate(qos: DispatchQoS,
                       predicate: @escaping (_ value: Success) -> Bool, message: String = "") -> Deferred<Success, Error>
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    return validate(queue: queue, predicate: predicate, message: message)
  }

  /// Insert a validation step in a chain of Deferred.
  ///
  /// Pass `Success` through if the predicate returns normally, otherwise replace it by the `Error` thrown by the predicate.
  ///
  /// - parameter queue: the `DispatchQueue` to attach to the new `Deferred`; defaults to `self`'s queue.
  /// - parameter predicate: a closure that validates the passed-in `Success` by either returning normally or throwing
  /// - returns: a `Deferred` reference holding a validated `Success`
  /// - parameter value: the value to be validated

  public func validate(queue: DispatchQueue? = nil,
                       predicate: @escaping (_ value: Success) throws -> Void) -> Deferred<Success, Error>
  {
    return self.tryMap(queue: queue) {
      value in
      try predicate(value)
      return value
    }
  }

  /// Insert a validation step in a chain of Deferred.
  ///
  /// Pass `Success` through if the predicate returns normally, otherwise replace it by the `Error` thrown by the predicate.
  ///
  /// - parameter qos: the QoS at which to execute the transform and the new `Deferred`'s notifications
  /// - parameter predicate: a closure that validates the passed-in `Success` by either returning normally or throwing
  /// - returns: a `Deferred` reference holding a validated `Success`
  /// - parameter value: the value to be validated

  public func validate(qos: DispatchQoS,
                       predicate: @escaping (_ value: Success) throws -> Void) -> Deferred<Success, Error>
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

  public func deferred(queue: DispatchQueue) -> Deferred<Wrapped, Invalidation>
  {
    switch self
    {
    case .some(let value):
      return Deferred(queue: queue, value: value)
    case .none:
      return Deferred(queue: queue, error: Invalidation.invalid("initialized from a nil Optional"))
    }
  }

  /// Create a `Deferred` from this `Optional`.
  ///
  /// If `optional` is `nil` then `Deferred` will be resolved with the error `DeferredError.invalid`
  ///
  /// - parameter qos: the QoS at which to perform notifications for the new `Deferred`; defaults to the current QoS class.

  public func deferred(qos: DispatchQoS = .current) -> Deferred<Wrapped, Invalidation>
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    return self.deferred(queue: queue)
  }
}
