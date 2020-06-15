//
//  deferred.swift
//  deferred
//
//  Created by Guillaume Lessard on 2015-07-09.
//  Copyright © 2015-2020 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics

/// An asynchronous computation.
///
/// A `Deferred` starts out unresolved, in the `.waiting` state.
/// It may then enter the `.executing` state, and may eventually become resolved,
/// either having `.succeeded` or `.errored`.
///
/// A `Deferred` that becomes resolved, will henceforth always be resolved: it can no longer mutate.
///
/// The `get()` function will return the value of the computation's `Result` (or throw a `Failure`),
/// blocking until it becomes available. If the result of the computation is known when `get()` is called,
/// it will return immediately.
/// The properties `value` and `error` are convenient non-throwing (but blocking) wrappers  for the `get()` method.
///
/// Closures supplied to the `enqueue` function will be called after the `Deferred` has become resolved.
/// The functions `map`, `flatMap`, `notify` and others are wrappers that add functionality to the `enqueue` function.

open class Deferred<Success, Failure: Error>
{
  let queue: DispatchQueue

  private let deferredState = UnsafeMutablePointer<AtomicInt>.allocate(capacity: 1)

  deinit {
    let current = CAtomicsLoad(deferredState, .acquire)
    if let resolved = current.resolution(for: Deferred.self)
    {
      resolved.deinitialize(count: 1)
      resolved.deallocate()
    }
    else if let waiters = current.waiterQueue(for: Deferred.self)
    {
      deallocateWaiters(waiters)
    }
    else if let taskp = current.deferredTask(for: Deferred.self)
    {
      taskp.deinitialize(count: 1)
      taskp.deallocate()
    }
    deferredState.deallocate()
  }

  // MARK: designated initializers

  fileprivate init(queue: DispatchQueue)
  {
    self.queue = queue
    CAtomicsInitialize(deferredState, Int(state: .waiting))
  }

  /// Initialize as resolved with a `Result`
  ///
  /// - parameter queue: the dispatch queue upon which to execute future notifications for this `Deferred`
  /// - parameter result: the `Result` of this `Deferred`

  public init(queue: DispatchQueue, result: Result<Success, Failure>)
  {
    self.queue = queue
    let resolved = UnsafeMutablePointer<Result<Success, Failure>>.allocate(capacity: 1)
    resolved.initialize(to: result)
    CAtomicsInitialize(deferredState, Int(resolved: resolved))
  }

  /// Initialize with a task to be computed in the background, on the specified queue
  ///
  /// - parameter queue: the `DispatchQueue` on which the computation (and notifications) will be executed
  /// - parameter task:  the computation to be performed

  public init(queue: DispatchQueue, task: @escaping (Resolver<Success, Failure>) -> Void)
  {
    self.queue = queue
    let taskp = UnsafeMutablePointer<DeferredTask<Success, Failure>>.allocate(capacity: 1)
    taskp.initialize(to: DeferredTask(task: task))
    CAtomicsInitialize(deferredState, Int(task: taskp))
  }

  /// Initialize with a task to be executed immediately
  ///
  /// The closure received as a parameter is executed immediately, on the current thread.
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed
  /// - parameter task:  the computation to be performed

  public init(notifyingOn queue: DispatchQueue, synchronous task: (Resolver<Success, Failure>) -> Void)
  {
    self.queue = queue
    CAtomicsInitialize(deferredState, Int(state: .executing))
    task(Resolver(self))
  }

  // MARK: convenience initializers

  /// Initialize with a task to be computed in the background
  ///
  /// - parameter qos:  the QoS at which the computation (and notifications) should be performed; defaults to the current QoS class.
  /// - parameter task: a computation to be performed

  public convenience init(qos: DispatchQoS = .current, task: @escaping (Resolver<Success, Failure>) -> Void)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, task: task)
  }

  /// Initialize with a task to be executed immediately
  ///
  /// The closure received as a parameter is executed immediately, on the current thread.
  ///
  /// - parameter qos:  the QoS at which the notifications will be performed.
  /// - parameter task: the computation to be performed.

  public convenience init(notifyingAt qos: DispatchQoS, synchronous task: (Resolver<Success, Failure>) -> Void)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(notifyingOn: queue, synchronous: task)
  }

  /// Initialize as resolved with a `Success`
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.
  /// - parameter value: the value of this `Deferred`

  public convenience init(qos: DispatchQoS = .current, value: Success)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, value: value)
  }

  /// Initialize as resolved with a `Success`
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed
  /// - parameter value: the value of this `Deferred`

  public convenience init(queue: DispatchQueue, value: Success)
  {
    self.init(queue: queue, result: .success(value))
  }

  /// Initialize as resolved with a `Failure`
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.
  /// - parameter error: the error state of this `Deferred`

  public convenience init(qos: DispatchQoS = .current, error: Failure)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, error: error)
  }

  /// Initialize as resolved with a `Failure`
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed
  /// - parameter error: the error state of this `Deferred`

  public convenience init(queue: DispatchQueue, error: Failure)
  {
    self.init(queue: queue, result: .failure(error))
  }

  // MARK: resolve()

  /// Set the `Result` of this `Deferred` and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve()` will fail and return `false`.
  ///
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter result: the intended `Result` to resolve this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  fileprivate func resolve(_ result: Result<Success, Failure>)
  {
    var current = CAtomicsLoad(deferredState, .relaxed)
    guard current.state != .resolved else { return }

    let resolved = UnsafeMutablePointer<Result<Success, Failure>>.allocate(capacity: 1)
    resolved.initialize(to: result)

    let final = Int(resolved: resolved)
    current = CAtomicsLoad(deferredState, .relaxed)
    repeat {
      if current.state == .resolved
      {
        resolved.deinitialize(count: 1)
        resolved.deallocate()
        return
      }
      // The atomic compare-and-swap operation uses memory order `.acqrel`.
      // "release" ordering ensures visibility of changes to `resolvedPointer(from:)` above to another thread.
      // "acquire" ordering ensures visibility of changes to `waiterQueue(from:)` below from another thread.
    } while !CAtomicsCompareAndExchangeWeak(deferredState, &current, final, .acqrel, .relaxed)

    precondition(current.state != .resolved)
    if let waiters = current.waiterQueue(for: Deferred.self)
    {
      notifyWaiters(queue, waiters, result)
    }
    else if let taskp = current.deferredTask(for: Deferred.self)
    {
      taskp.deinitialize(count: 1)
      taskp.deallocate()
    }

    // This `Deferred` has been resolved
  }

  /// Convert a `Cancellation` to the correct type of `Failure` for this `Deferred`
  ///
  /// This is a customization point for subclasses of `Deferred`, and
  /// is of limited utility to client code. It can be used to determine
  /// whether a `Deferred` is at all capable of cancellation, but little else.
  ///
  /// - returns: a converted `Failure` instance, or `nil` if cancellation will fail.

  open func convertCancellation<E: Error>(_ error: E) -> Failure?
  {
    return (error as? Cancellation) as? Failure
  }

  /// Attempt to cancel this `Deferred`.
  ///
  /// This is a customization point for subclasses of `Deferred` but
  /// there are only limited cases where it could be useful.
  ///
  /// - parameter error: the Cancellation error to use in resolving this `Deferred`

  open func cancel<E: Error>(_ error: E)
  {
    if let error = convertCancellation(error)
    {
      resolve(.failure(error))
    }
  }

  // MARK: retain source

  /// Keep a strong reference to `source` until this `Deferred` has been resolved.
  ///
  /// The implication here is that `source` is needed as an input to `self`.
  ///
  /// - parameter source: a reference to keep alive until this `Deferred` is resolved.

  fileprivate func retainSource(_ source: AnyObject)
  {
    let current = CAtomicsLoad(deferredState, .relaxed)
    if current.state != .resolved
    {
      let waiter = UnsafeMutablePointer<Waiter<Success, Failure>>.allocate(capacity: 1)
      waiter.initialize(to: Waiter(source: source))

      if enqueueWaiter(waiter: waiter)
      { // waiter is now enqueued; it will be deallocated at a later time by notifyWaiters()
        return
      }

      // this Deferred has become resolved; clean up
      waiter.deinitialize(count: 1)
      waiter.deallocate()
    }
  }

  private func enqueueWaiter(waiter: UnsafeMutablePointer<Waiter<Success, Failure>>) -> Bool
  {
    var current = CAtomicsLoad(deferredState, .relaxed)
    let desired = Int(waiter: waiter)
    repeat {
      if current.state == .resolved { return false }

      waiter.pointee.next = current.waiterQueue(for: Deferred.self)
      // read-modify-write `deferredState` with memory_order_release.
      // this means that this write is in the release sequence of all previous writes.
      // a subsequent read-from `deferredState` will therefore synchronize-with all previous writes.
      // this matters for the `resolve(_:)` function, which operates on the queue of `Waiter` instances.
    } while !CAtomicsCompareAndExchangeWeak(deferredState, &current, desired, .release, .relaxed)

    if let taskp = current.deferredTask(for: Deferred.self)
    { // initial task needs to run
      executeDeferredTask(taskp)
    }
    return true
  }

  // MARK: enqueue notification and start execution

  /// Enqueue a closure to be performed asynchronously after this `Deferred` becomes resolved.
  ///
  /// This operation is lock-free and thread-safe.
  /// Multiple threads can call this method at once; they will succeed in turn.
  ///
  /// Before `self` has been resolved, the effect of `enqueue()` is to add the closure
  /// to a list of closures to be called once this `Deferred` has been resolved.
  ///
  /// Before `self` has been resolved, the effect of `enqueue()` is to immediately
  /// enqueue the closure for execution.
  ///
  /// Note that the enqueued closure will does not modify `task`, and will not extend the lifetime of `self`.
  /// If you need to extend the lifetime of `self` until the closure executes, use `notify()`.
  ///
  /// - parameter queue: the `DispatchQueue` on which to dispatch this notification when ready; defaults to `self`'s queue.
  /// - parameter boostQoS: whether `enqueue` should attempt to boost the QoS if `queue.qos` is higher than `self.qos`; defaults to `true`
  /// - parameter task: a closure to be executed after `self` becomes resolved.
  /// - parameter result: the `Result` of `self`

  open func notify(queue: DispatchQueue? = nil, boostQoS: Bool = true, handler: @escaping (_ result: Result<Success, Failure>) -> Void)
  {
    var current = CAtomicsLoad(deferredState, .acquire)
    if current.state != .resolved
    {
      let waiter = UnsafeMutablePointer<Waiter<Success, Failure>>.allocate(capacity: 1)
      waiter.initialize(to: Waiter(queue, handler))

      if boostQoS, let qos = queue?.qos, qos > self.queue.qos
      { // try to raise `self.queue`'s QoS if the notification needs to execute at a higher QoS
        self.queue.async(qos: qos, flags: [.enforceQoS, .barrier], execute: {})
      }

      if enqueueWaiter(waiter: waiter)
      { // waiter is now enqueued; it will be deallocated at a later time by notifyWaiters()
        return
      }

      // this Deferred has become resolved; clean up
      waiter.deinitialize(count: 1)
      waiter.deallocate()
      current = CAtomicsLoad(deferredState, .acquire)
    }

    // this Deferred is resolved
    let q = queue ?? self.queue
    let resolved = current.resolution(for: Deferred.self)!
    q.async(execute: { [result = resolved.pointee] in handler(result) })
  }

  /// Change the state of this `Deferred` from `.waiting` to `.executing`

  public func beginExecution()
  {
    var current = CAtomicsLoad(deferredState, .relaxed)
    let desired = Int(state: .executing)
    repeat {
      guard current.state == .waiting else { return }
      // execution state has not yet been marked as begun

      // read-modify-write `deferredState` with memory_order_release.
      // this means that this write is in the release sequence of all previous writes.
      // a subsequent read-from `deferredState` will therefore synchronize-with all previous writes.
      // this matters for the `resolve(_:)` function, which operates on the queue of `Waiter` instances.
    } while !CAtomicsCompareAndExchangeWeak(deferredState, &current, desired, .release, .relaxed)

    if let taskp = current.deferredTask(for: Deferred.self) { executeDeferredTask(taskp) }
  }

  private func executeDeferredTask(_ taskp: UnsafeMutablePointer<DeferredTask<Success, Failure>>)
  {
    queue.async {
      [self] in
      withExtendedLifetime(self) { taskp.pointee.task(Resolver($0)) }
      taskp.deinitialize(count: 1)
      taskp.deallocate()
    }
  }
}

extension Deferred where Failure == Error
{
  /// Initialize with a task to be computed on the specified queue
  ///
  /// - parameter queue: the `DispatchQueue` on which the computation (and notifications) will be executed
  /// - parameter task:  the computation to be performed

  public convenience init(queue: DispatchQueue, task: @escaping () throws -> Success)
  {
    self.init(queue: queue, task: { r in r.resolve(Result(catching: task)) })
  }

  /// Initialize with a task to be computed in the background
  ///
  /// - parameter qos:  the QoS at which the computation (and notifications) should be performed; defaults to the current QoS class.
  /// - parameter task: a computation to be performed

  public convenience init(qos: DispatchQoS = .current, task: @escaping () throws -> Success)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, task: task)
  }
}

extension Deferred where Failure == Never
{
  /// Initialize with a task to be computed on the specified queue
  ///
  /// - parameter queue: the `DispatchQueue` on which the computation (and notifications) will be executed
  /// - parameter task:  the computation to be performed

  public convenience init(queue: DispatchQueue, task: @escaping () -> Success)
  {
    self.init(queue: queue, task: { r in r.resolve(value: task()) })
  }

  /// Initialize with a task to be computed in the background
  ///
  /// - parameter qos:  the QoS at which the computation (and notifications) should be performed; defaults to the current QoS class.
  /// - parameter task: a computation to be performed

  public convenience init(qos: DispatchQoS = .current, task: @escaping () -> Success)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, task: task)
  }
}

// FIXME: Should be a single conditional extension
// Unfortunately, it should be `where Cancellation is Failure`,
// which is not (yet) a valid condition.
// It might be nice to conform to the `Cancellable` protocol defined by `Combine`.

extension Deferred where Failure == Cancellation
{
  /// Attempt to cancel this `Deferred`
  ///
  /// A successful cancellation will result in a `Deferred` equivalent to as if it had been initialized as follows:
  /// ```
  /// Deferred<Success, Cancellation>(error: Cancellation.canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation. Defaults to an empty `String`.
  /// - returns: whether the cancellation was performed successfully.

  public func cancel(_ reason: String = "")
  {
    cancel(Cancellation.canceled(reason))
  }
}

extension Deferred where Failure == Error
{
  /// Attempt to cancel this `Deferred`
  ///
  /// A successful cancellation will result in a `Deferred` equivalent to as if it had been initialized as follows:
  /// ```
  /// Deferred<Success, Error>(error: Cancellation.canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation. Defaults to an empty `String`.
  /// - returns: whether the cancellation was performed successfully.

  public func cancel(_ reason: String = "")
  {
    cancel(Cancellation.canceled(reason))
  }
}

extension Deferred: ResultWrapper
{
  /// Get this `Deferred`'s `Result`, blocking if necessary until it exists.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s `Result`

  public var result: Result<Success, Failure> {
    var current = CAtomicsLoad(deferredState, .acquire)
    if current.state != .resolved
    {
      if let qosClass = DispatchQoS.QoSClass.current, qosClass > queue.qos.qosClass
      { // try to boost the QoS class of the running task if it is lower than the current thread's QoS
        queue.async(qos: DispatchQoS(qosClass: qosClass, relativePriority: 0),
                    flags: [.enforceQoS, .barrier], execute: {})
      }
      let s = DispatchSemaphore(value: 0)
      self.notify(boostQoS: false, handler: { _ in s.signal() })
      s.wait()
      current = CAtomicsLoad(deferredState, .acquire)
    }

    // this Deferred is resolved
    let resolved = current.resolution(for: Deferred.self)!
    return resolved.pointee
  }
}

extension Deferred
{
  // MARK: get data from a Deferred

  /// Query the current state of this `Deferred`
  /// - returns: a `deferredState.pointee` that describes this `Deferred`

  public var state: DeferredState {
    return CAtomicsLoad(deferredState, .relaxed).state
  }

  /// Query whether this `Deferred` has become resolved.
  /// - returns: `true` iff this `Deferred` has become resolved.

  public var isResolved: Bool {
    return CAtomicsLoad(deferredState, .relaxed).state == .resolved
  }

  /// Get this `Deferred`'s `Result` if has been resolved, `nil` otherwise.
  ///
  /// This call is non-blocking and wait-free.
  ///
  /// - returns: this `Deferred`'s `Result`, or `nil`

  public func peek() -> Result<Success, Failure>?
  {
    let current = CAtomicsLoad(deferredState, .acquire)
    guard let resolved = current.resolution(for: Deferred.self) else { return nil }
    return resolved.pointee
  }

  /// Get the QoS of this `Deferred`'s queue
  /// - returns: the QoS of this `Deferred`'s queue

  public var qos: DispatchQoS { return self.queue.qos }
}

public struct Resolver<Success, Failure: Error>
{
  private weak var deferred: Deferred<Success, Failure>?
  private let resolve: (Result<Success, Failure>) -> Void

  fileprivate init(_ deferred: Deferred<Success, Failure>)
  {
    self.deferred = deferred
    self.resolve = { [weak deferred] in deferred?.resolve($0) }
  }

  /// Resolve the underlying `Deferred` and execute all of its notifications.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`

  public func resolve(_ result: Result<Success, Failure>)
  {
    resolve(result)
  }

  /// Resolve the underlying `Deferred` with a value, and execute all of its notifications.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  public func resolve(value: Success)
  {
    resolve(.success(value))
  }

  /// Resolve the underlying `Deferred` with an error, and execute all of its notifications.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter error: the intended error for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  public func resolve(error: Failure)
  {
    resolve(.failure(error))
  }

  /// Change the state of the underlying `Deferred` from `.waiting` to `.executing`

  public func beginExecution()
  {
    deferred?.beginExecution()
  }

  /// Query the Quality-of-Service used by this `Resolver`'s underlying `Deferred`

  public var qos: DispatchQoS { return deferred?.queue.qos ?? .unspecified }

  /// Query whether the underlying `Deferred` still exists and is also unresolved

  public var needsResolution: Bool {
    let state = deferred?.state
    return state != nil && state != .resolved
  }

  /// Enqueue a notification to be performed asynchronously after our `Deferred` becomes resolved.
  ///
  /// - parameter queue: the `DispatchQueue` on which to dispatch this notification when ready; defaults to `self`'s queue.
  /// - parameter task: a closure to be executed as a notification
  /// - parameter result: the `Result` to which our `Deferred` was resolved

  public func notify(handler: @escaping () -> Void)
  {
    deferred?.notify(handler: { _ in handler() })
  }

  /// Keep a strong reference to `source` until this `Deferred` has been resolved.
  ///
  /// The implication here is that `source` is needed as an input to `self`.
  ///
  /// - parameter source: a reference to keep alive until this `Deferred` is resolved.

  public func retainSource(_ source: AnyObject)
  {
    deferred?.retainSource(source)
  }
}

// FIXME: Should be a single conditional extension
// Unfortunately, it should be `where Cancellation is Failure`,
// which is not (yet) a valid condition.

extension Resolver where Failure == Cancellation
{
  /// Attempt to cancel the underlying `Deferred`, and report on whether cancellation happened successfully.
  ///
  /// A successful cancellation will result in a `Deferred` equivalent to as if it had been initialized as follows:
  /// ```
  /// Deferred<Success>(error: DeferredError.canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation. Defaults to an empty `String`.
  /// - returns: whether the cancellation was performed successfully.

  public func cancel(_ reason: String = "")
  {
    cancel(.canceled(reason))
  }

  /// Attempt to cancel the underlying `Deferred`, and report on whether cancellation happened successfully.
  ///
  /// - parameter error: a `DeferredError` detailing the reason for the attempted cancellation.
  /// - returns: whether the cancellation was performed successfully.

  public func cancel(_ error: Cancellation)
  {
    deferred?.cancel(error)
  }
}

extension Resolver where Failure == Error
{
  /// Attempt to cancel the underlying `Deferred`, and report on whether cancellation happened successfully.
  ///
  /// A successful cancellation will result in a `Deferred` equivalent to as if it had been initialized as follows:
  /// ```
  /// Deferred<Success>(error: DeferredError.canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation. Defaults to an empty `String`.
  /// - returns: whether the cancellation was performed successfully.

  public func cancel(_ reason: String = "")
  {
    cancel(.canceled(reason))
  }

  /// Attempt to cancel the underlying `Deferred`, and report on whether cancellation happened successfully.
  ///
  /// - parameter error: a `DeferredError` detailing the reason for the attempted cancellation.
  /// - returns: whether the cancellation was performed successfully.

  public func cancel(_ error: Cancellation)
  {
    deferred?.cancel(error)
  }
}

extension Deferred
{
  /// Obtain an unresolved `Deferred` with a paired `Resolver`
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed

  public static func CreatePair(queue: DispatchQueue) -> (resolver: Resolver<Success, Failure>, deferred: Deferred<Success, Failure>)
  {
    let d = Deferred<Success, Failure>(queue: queue)
    return (Resolver(d), d)
  }

  /// Obtain an unresolved `Deferred` with a paired `Resolver`
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.

  public static func CreatePair(qos: DispatchQoS = .current) -> (resolver: Resolver<Success, Failure>, deferred: Deferred<Success, Failure>)
  {
    let queue = DispatchQueue(label: "tbd", qos: qos)
    return CreatePair(queue: queue)
  }
}
