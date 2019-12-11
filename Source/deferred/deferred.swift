//
//  deferred.swift
//  deferred
//
//  Created by Guillaume Lessard on 2015-07-09.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch
import CAtomics

/// The possible states of a `Deferred`.
///
/// Must be a top-level type because Deferred is generic.

public enum DeferredState: Int, Equatable, Hashable
{
  case waiting = 0x0, executing = 0x1, resolved = 0x3
}

private extension Int
{
  static let waiting =   DeferredState.waiting.rawValue
  static let executing = DeferredState.executing.rawValue
  static let resolved =  DeferredState.resolved.rawValue
  private static let stateMask = 0x3

  init(_ pointer: UnsafeMutableRawPointer, tag: DeferredState)
  {
    self = Int(bitPattern: pointer) | (tag.rawValue & .stateMask)
  }

  var isResolved: Bool { return tag == .resolved }

  var tag: DeferredState { return DeferredState(rawValue: self & .stateMask)! }
  var ptr: UnsafeMutableRawPointer? { return UnsafeMutableRawPointer(bitPattern: self & ~.stateMask) }
}

private struct DeferredTask<Success, Failure: Error>
{
  let task: (Resolver<Success, Failure>) -> Void
}

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

  private var deferredState = UnsafeMutablePointer<AtomicInt>.allocate(capacity: 1)

  /// Get a pointer to a `DeferredTask` that will resolve this `Deferred`

  private func deferredTask(from state: Int) -> UnsafeMutablePointer<DeferredTask<Success, Failure>>?
  {
    guard state.tag == .waiting else { return nil }
    return state.ptr?.assumingMemoryBound(to: DeferredTask<Success, Failure>.self)
  }

  /// Get a pointer to a `Result` for a resolved `Deferred`.
  /// `state` must have been read with `.acquire` memory ordering in order
  /// to safely see all the changes from the thread that resolved this `Deferred`.

  private func resolvedPointer(from state: Int) -> UnsafeMutablePointer<Result<Success, Failure>>?
  {
    guard state.tag == .resolved else { return nil }
    return state.ptr?.assumingMemoryBound(to: Result<Success, Failure>.self)
  }

  /// Get a pointer to the first `Waiter` for an unresolved `Deferred`.
  /// `state` must have been read with `.acquire` memory ordering in order
  /// to safely see all the changes from the thread that last enqueued a `Waiter`.

  private func waiterQueue(from state: Int) -> UnsafeMutablePointer<Waiter<Success, Failure>>?
  {
    guard state.tag == .executing else { return nil }
    return state.ptr?.assumingMemoryBound(to: Waiter<Success, Failure>.self)
  }

  deinit
  {
    let state = CAtomicsLoad(deferredState, .acquire)
    if let resolved = resolvedPointer(from: state)
    {
      resolved.deinitialize(count: 1)
      resolved.deallocate()
    }
    else if let waiters = waiterQueue(from: state)
    {
      deallocateWaiters(waiters)
    }
    else if let taskp = deferredTask(from: state)
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
    CAtomicsInitialize(deferredState, .waiting)
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
    CAtomicsInitialize(deferredState, Int(resolved, tag: .resolved))
  }

  /// Initialize with a task to be computed on the specified queue
  ///
  /// - parameter queue: the `DispatchQueue` on which the computation (and notifications) will be executed
  /// - parameter task:  the computation to be performed

  public init(queue: DispatchQueue, task: @escaping (Resolver<Success, Failure>) -> Void)
  {
    self.queue = queue
    let taskp = UnsafeMutablePointer<DeferredTask<Success, Failure>>.allocate(capacity: 1)
    taskp.initialize(to: DeferredTask(task: task))
    CAtomicsInitialize(deferredState, Int(taskp, tag: .waiting))
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
    self.init(queue: queue, result: Result<Success, Failure>(value: value))
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
    self.init(queue: queue, result: Result<Success, Failure>(error: error))
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

  @discardableResult
  fileprivate func resolve(_ result: Result<Success, Failure>) -> Bool
  {
    var state = CAtomicsLoad(deferredState, .relaxed)
    guard state.tag != .resolved else { return false }

    let resolved = UnsafeMutablePointer<Result<Success, Failure>>.allocate(capacity: 1)
    resolved.initialize(to: result)

    let final = Int(resolved, tag: .resolved)
    state = CAtomicsLoad(deferredState, .relaxed)
    repeat {
      if state.tag == .resolved
      {
        resolved.deinitialize(count: 1)
        resolved.deallocate()
        return false
      }
      // The atomic compare-and-swap operation uses memory order `.acqrel`.
      // "release" ordering ensures visibility of changes to `resolvedPointer(from:)` above to another thread.
      // "acquire" ordering ensures visibility of changes to `waiterQueue(from:)` below from another thread.
    } while !CAtomicsCompareAndExchange(deferredState, &state, final, .weak, .acqrel, .relaxed)

    precondition(state.tag != .resolved)
    if let waiters = waiterQueue(from: state)
    {
      notifyWaiters(queue, waiters, result)
    }
    else if let taskp = deferredTask(from: state)
    {
      taskp.deinitialize(count: 1)
      taskp.deallocate()
    }

    // This `Deferred` has been resolved
    return true
  }

  /// Attempt to cancel this `Deferred`
  ///
  /// - parameter error: a `DeferredError` detailing the reason for the attempted cancellation.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  open func cancel(_ error: Cancellation) -> Bool
  {
    guard let error = error as? Failure else { return false }
    return resolve(.failure(error))
  }

  // MARK: retain source

  /// Keep a strong reference to `source` until this `Deferred` has been resolved.
  ///
  /// The implication here is that `source` is needed as an input to `self`.
  ///
  /// - parameter source: a reference to keep alive until this `Deferred` is resolved.

  fileprivate func retainSource(_ source: AnyObject)
  {
    var state = CAtomicsLoad(deferredState, .relaxed)
    if !state.isResolved
    {
      let waiter = UnsafeMutablePointer<Waiter<Success, Failure>>.allocate(capacity: 1)
      waiter.initialize(to: Waiter(source: source))

      repeat {
        waiter.pointee.next = waiterQueue(from: state)
        let newState = Int(waiter, tag: .executing)
        // read-modify-write `deferredState` with memory_order_release.
        // this means that this write is in the release sequence of all previous writes.
        // a subsequent read-from `deferredState` will therefore synchronize-with all previous writes.
        // this matters for the `resolve(_:)` function, which operates on the queue of `Waiter` instances.
        if CAtomicsCompareAndExchange(deferredState, &state, newState, .weak, .release, .relaxed)
        { // waiter is now enqueued; it will be deallocated at a later time by notifyWaiters()
          if let taskp = deferredTask(from: state)
          { // we need to execute the task
            self.queue.async {
              [self] in
              withExtendedLifetime(self) { taskp.pointee.task(Resolver(self)) }
              taskp.deinitialize(count: 1)
              taskp.deallocate()
            }
          }
          return
        }
      } while !state.isResolved

      // this Deferred has become resolved; clean up
      waiter.deinitialize(count: 1)
      waiter.deallocate()
    }
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
    var state = CAtomicsLoad(deferredState, .acquire)
    if !state.isResolved
    {
      let waiter = UnsafeMutablePointer<Waiter<Success, Failure>>.allocate(capacity: 1)
      waiter.initialize(to: Waiter(queue, handler))

      if boostQoS, let qos = queue?.qos, qos > self.queue.qos
      { // try to raise `self.queue`'s QoS if the notification needs to execute at a higher QoS
        self.queue.async(qos: qos, flags: [.enforceQoS, .barrier], execute: {})
      }

      repeat {
        waiter.pointee.next = waiterQueue(from: state)
        let newState = Int(waiter, tag: .executing)
        // read-modify-write `deferredState` with memory_order_release.
        // this means that this write is in the release sequence of all previous writes.
        // a subsequent read-from `deferredState` will therefore synchronize-with all previous writes.
        // this matters for the `resolve(_:)` function, which operates on the queue of `Waiter` instances.
        if CAtomicsCompareAndExchange(deferredState, &state, newState, .weak, .release, .relaxed)
        { // waiter is now enqueued; it will be deallocated at a later time by notifyWaiters()
          if let taskp = deferredTask(from: state)
          { // we need to execute the task
            self.queue.async {
              [self] in
              withExtendedLifetime(self) { taskp.pointee.task(Resolver(self)) }
              taskp.deinitialize(count: 1)
              taskp.deallocate()
            }
          }
          return
        }
      } while !state.isResolved

      // this Deferred has become resolved; clean up
      waiter.deinitialize(count: 1)
      waiter.deallocate()
      state = CAtomicsLoad(deferredState, .acquire)
    }

    // this Deferred is resolved
    let q = queue ?? self.queue
    let resolved = resolvedPointer(from: state)!
    q.async(execute: { [result = resolved.pointee] in handler(result) })
  }

  /// Change the state of this `Deferred` from `.waiting` to `.executing`

  public func beginExecution()
  {
    var state = CAtomicsLoad(deferredState, .relaxed)
    repeat {
      guard state.tag == .waiting else { return }
      // execution state has not yet been marked as begun

      // read-modify-write `deferredState` with memory_order_release.
      // this means that this write is in the release sequence of all previous writes.
      // a subsequent read-from `deferredState` will therefore synchronize-with all previous writes.
      // this matters for the `resolve(_:)` function, which operates on the queue of `Waiter` instances.
    } while !CAtomicsCompareAndExchange(deferredState, &state, .executing, .weak, .release, .relaxed)

    if let taskp = deferredTask(from: state)
    { // we need to execute the task
      self.queue.async {
        [self] in
        withExtendedLifetime(self) { taskp.pointee.task(Resolver(self)) }
        taskp.deinitialize(count: 1)
        taskp.deallocate()
      }
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
  public convenience init(queue: DispatchQueue, task: @escaping () -> Success)
  {
    self.init(queue: queue, task: { r in r.resolve(value: task()) })
  }

  public convenience init(qos: DispatchQoS = .current, task: @escaping () -> Success)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, task: task)
  }
}

extension Deferred
{
  /// Attempt to cancel this `Deferred`
  ///
  /// A successful cancellation will result in a `Deferred` equivalent to as if it had been initialized as follows:
  /// ```
  /// Deferred<Success>(error: DeferredError.canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation. Defaults to an empty `String`.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  public final func cancel(_ reason: String = "") -> Bool
  {
    return cancel(.canceled(reason))
  }
}

extension Deferred
{
  // MARK: get data from a Deferred

  /// Query the current state of this `Deferred`
  /// - returns: a `deferredState.pointee` that describes this `Deferred`

  public var state: DeferredState {
    let state = CAtomicsLoad(deferredState, .acquire)
    return state.tag
  }

  /// Query whether this `Deferred` has become resolved.
  /// - returns: `true` iff this `Deferred` has become resolved.

  public var isResolved: Bool {
    return CAtomicsLoad(deferredState, .relaxed).isResolved
  }


  /// Get this `Deferred`'s `Result`, blocking if necessary until it exists.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s `Result`

  public var result: Result<Success, Failure> {
    var state = CAtomicsLoad(deferredState, .acquire)
    if state.isResolved == false
    {
      if let current = DispatchQoS.QoSClass.current, current > queue.qos.qosClass
      { // try to boost the QoS class of the running task if it is lower than the current thread's QoS
        queue.async(qos: DispatchQoS(qosClass: current, relativePriority: 0),
                    flags: [.enforceQoS, .barrier], execute: {})
      }
      let s = DispatchSemaphore(value: 0)
      self.notify(boostQoS: false, handler: { _ in s.signal() })
      s.wait()
      state = CAtomicsLoad(deferredState, .acquire)
    }

    // this Deferred is resolved
    let resolved = resolvedPointer(from: state)!
    return resolved.pointee
  }

  /// Get this `Deferred`'s value, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with a `Failure`, that `Failure` is thrown.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved `Success`, or throws
  /// - throws: this `Deferred`'s resolved `Failure` if it cannot return a `Success`

  public func get() throws -> Success
  {
    return try result.get()
  }

  /// Get this `Deferred`'s `Result` if has been resolved, `nil` otherwise.
  ///
  /// This call is non-blocking and wait-free.
  ///
  /// - returns: this `Deferred`'s `Result`, or `nil`

  public func peek() -> Result<Success, Failure>?
  {
    let state = CAtomicsLoad(deferredState, .acquire)
    guard let resolved = resolvedPointer(from: state) else { return nil }
    return resolved.pointee
  }

  /// Get this `Deferred`'s value, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with a `Failure`, return nil.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved value, or `nil`

  public var value: Success? {
    return result.value
  }

  /// Get this `Deferred`'s error state, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with a `Success`, return nil.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved error state, or `nil`

  public var error: Failure? {
    return result.error
  }

  /// Get the QoS of this `Deferred`'s queue
  /// - returns: the QoS of this `Deferred`'s queue

  public var qos: DispatchQoS { return self.queue.qos }
}

public struct Resolver<Success, Failure: Error>
{
  private weak var deferred: Deferred<Success, Failure>?
  private let resolve: (Result<Success, Failure>) -> Bool

  fileprivate init(_ deferred: Deferred<Success, Failure>)
  {
    self.deferred = deferred
    self.resolve = { [weak deferred] in deferred?.resolve($0) ?? false }
  }

  /// Resolve the underlying `Deferred` and execute all of its notifications.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  public func resolve(_ result: Result<Success, Failure>) -> Bool
  {
    return resolve(result)
  }

  /// Resolve the underlying `Deferred` with a value, and execute all of its notifications.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  public func resolve(value: Success) -> Bool
  {
    return resolve(Result<Success, Failure>(value: value))
  }

  /// Resolve the underlying `Deferred` with an error, and execute all of its notifications.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve` will fail and return `false`.
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter error: the intended error for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  public func resolve(error: Failure) -> Bool
  {
    return resolve(Result<Success, Failure>(error: error))
  }

  /// Attempt to cancel the underlying `Deferred`, and report on whether cancellation happened successfully.
  ///
  /// A successful cancellation will result in a `Deferred` equivalent to as if it had been initialized as follows:
  /// ```
  /// Deferred<Success>(error: DeferredError.canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation. Defaults to an empty `String`.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  public func cancel(_ reason: String = "") -> Bool
  {
    return cancel(.canceled(reason))
  }

  /// Attempt to cancel the underlying `Deferred`, and report on whether cancellation happened successfully.
  ///
  /// - parameter error: a `DeferredError` detailing the reason for the attempted cancellation.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  public func cancel(_ error: Cancellation) -> Bool
  {
    return deferred?.cancel(error) ?? false
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
