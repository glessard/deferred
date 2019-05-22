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

public enum DeferredState
{
  case waiting, executing, succeeded, errored
  /// Whether this `DeferredState` is resolved.
  /// returns: `true` iff this `DeferredState` represents one of the states where it is resolved
  public var isResolved: Bool { return self == .succeeded || self == .errored }
}

private extension Int
{
  static let waiting =   0x0
  static let executing = 0x1
  static let resolved =  0x3
  private static let stateMask = 0x3

  var isResolved: Bool { return (self & .stateMask) == .resolved }
  var state: Int { return self & .stateMask }
  var waiters: UnsafeMutableRawPointer? { return UnsafeMutableRawPointer(bitPattern: self & ~.stateMask) }
}

/// An asynchronous computation.
///
/// A `Deferred` starts out unresolved, in the `.waiting` state.
/// It may then enter the `.executing` state, and may eventually become resolved,
/// either having `.succeeded` or `.errored`.
///
/// A `Deferred` that becomes resolved, will henceforth always be resolved: it can no longer mutate.
///
/// The `get()` function will return the value of the computation's `Result` (or throw an `Error`),
/// blocking until it becomes available. If the result of the computation is known when `get()` is called,
/// it will return immediately.
/// The properties `value` and `error` are convenient non-throwing (but blocking) wrappers  for the `get()` method.
///
/// Closures supplied to the `enqueue` function will be called after the `Deferred` has become resolved.
/// The functions `map`, `flatMap`, `notify` and others are wrappers that add functionality to the `enqueue` function.

open class Deferred<Value>
{
  let queue: DispatchQueue

  private var resolved: Result<Value, Error>?
  private var deferredState = UnsafeMutablePointer<AtomicInt>.allocate(capacity: 1)

  deinit
  {
    let s = CAtomicsLoad(deferredState, .acquire)
    if !s.isResolved, let w = s.waiters
    {
      deallocateWaiters(w.assumingMemoryBound(to: Waiter<Value>.self))
    }
    deferredState.deallocate()
  }

  // MARK: designated initializers

  fileprivate init(queue: DispatchQueue)
  {
    self.queue = queue
    resolved = nil
    CAtomicsInitialize(deferredState, .waiting)
  }

  /// Initialize as resolved with a `Result`
  ///
  /// - parameter queue: the dispatch queue upon which to execute future notifications for this `Deferred`
  /// - parameter result: the `Result` of this `Deferred`

  public init(queue: DispatchQueue, result: Result<Value, Error>)
  {
    self.queue = queue
    resolved = result
    CAtomicsInitialize(deferredState, .resolved)
  }

  /// Initialize with a task to be computed on the specified queue
  ///
  /// - parameter queue: the `DispatchQueue` on which the computation (and notifications) will be executed
  /// - parameter task:  the computation to be performed

  public init(queue: DispatchQueue, task: @escaping () throws -> Value)
  {
    self.queue = queue
    resolved = nil
    CAtomicsInitialize(deferredState, .executing)

    queue.async {
      do {
        let value = try task()
        self.resolve(value: value)
      }
      catch {
        self.resolve(error: error)
      }
    }
  }

  // MARK: convenience initializers

  /// Initialize with a task to be computed in the background
  ///
  /// - parameter qos:  the QoS at which the computation (and notifications) should be performed; defaults to the current QoS class.
  /// - parameter task: a computation to be performed

  public convenience init(qos: DispatchQoS = .current, task: @escaping () throws -> Value)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, task: task)
  }

  /// Initialize as resolved with a `Value`
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.
  /// - parameter value: the value of this `Deferred`

  public convenience init(qos: DispatchQoS = .current, value: Value)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, value: value)
  }

  /// Initialize as resolved with a `Value`
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed
  /// - parameter value: the value of this `Deferred`

  public convenience init(queue: DispatchQueue, value: Value)
  {
    self.init(queue: queue, result: Result<Value, Error>(value: value))
  }

  /// Initialize as resolved with an `Error`
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.
  /// - parameter error: the error state of this `Deferred`

  public convenience init(qos: DispatchQoS = .current, error: Error)
  {
    let queue = DispatchQueue(label: "deferred", qos: qos)
    self.init(queue: queue, error: error)
  }

  /// Initialize as resolved with an `Error`
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed
  /// - parameter error: the error state of this `Deferred`

  public convenience init(queue: DispatchQueue, error: Error)
  {
    self.init(queue: queue, result: Result<Value, Error>(error: error))
  }

  // MARK: state changes / resolve

  /// Change the state of this `Deferred` from `.waiting` to `.executing`

  func beginExecution()
  {
    var current = CAtomicsLoad(deferredState, .relaxed)
    repeat {
      if current & .executing != 0
      { // execution state has already been marked as begun
        return
      }
    } while !CAtomicsCompareAndExchange(deferredState, &current, current | .executing, .weak, .acqrel, .acquire)
  }

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
  fileprivate func resolve(_ result: Result<Value, Error>) -> Bool
  {
    let original = CAtomicsLoad(deferredState, .relaxed)
    guard original.state != .resolved else { return false }

    let resolved = UnsafeMutablePointer<Result<Value, Error>>.allocate(capacity: 1)
    resolved.initialize(to: result)

    let final = Int(bitPattern: resolved) | .resolved
    var current = CAtomicsLoad(deferredState, .acquire)
    repeat {
      if current.state == .resolved
      {
        resolved.deinitialize(count: 1)
        resolved.deallocate()
        return false
      }
    } while !CAtomicsCompareAndExchange(deferredState, &current, final, .weak, .acqrel, .acquire)

    // This atomic swap operation uses memory order .acqrel.
    // "release" ordering ensures visibility of changes to `resolved` above to another thread.
    // "acquire" ordering ensures visibility of changes to `waitQueue` from another thread.
    // Any atomic load of `waiters` that precedes a possible use of `resolved`
    // *must* use memory order .acquire.

    precondition(current.isResolved == false)
    let waitQueue = current.waiters?.assumingMemoryBound(to: Waiter<Value>.self)
    notifyWaiters(queue, waitQueue, result)

    // This `Deferred` has been resolved
    return true
  }

  /// Resolve this `Deferred` with a `Value` and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve()` will fail and return `false`.
  ///
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter value: the intended value for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  fileprivate func resolve(value: Value) -> Bool
  {
    return resolve(Result<Value, Error>(value: value))
  }

  /// Resolve this `Deferred` with an `Error` and dispatch all notifications for execution.
  ///
  /// Note that a `Deferred` can only be resolved once.
  /// On subsequent calls, `resolve()` will fail and return `false`.
  ///
  /// This operation is lock-free and thread-safe.
  ///
  /// - parameter error: the intended error for this `Deferred`
  /// - returns: whether the call succesfully changed the state of this `Deferred`.

  @discardableResult
  fileprivate func resolve(error: Error) -> Bool
  {
    return resolve(Result<Value, Error>(error: error))
  }

  /// Keep a strong reference to `source` until this `Deferred` has been resolved.
  ///
  /// The implication here is that `source` is needed as an input to `self`.
  ///
  /// - parameter source: a reference to keep alive until this `Deferred` is resolved.

  fileprivate func retainSource(_ source: AnyObject)
  {
    var state = CAtomicsLoad(deferredState, .acquire)
    if !state.isResolved
    {
      let waiter = UnsafeMutablePointer<Waiter<Value>>.allocate(capacity: 1)
      waiter.initialize(to: Waiter(source: source))

      repeat {
        waiter.pointee.next = state.waiters?.assumingMemoryBound(to: Waiter<Value>.self)
        let newState = Int(bitPattern: waiter) | state.state
        if CAtomicsCompareAndExchange(deferredState, &state, newState, .weak, .release, .relaxed)
        { // waiter is now enqueued; it will be deallocated at a later time by notifyWaiters()
          return
        }
      } while !state.isResolved

      // this Deferred has become resolved; clean up
      waiter.deinitialize(count: 1)
      waiter.deallocate()
    }
  }

  // MARK: public interface

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

  open func notify(queue: DispatchQueue? = nil, boostQoS: Bool = true, handler: @escaping (_ result: Result<Value, Error>) -> Void)
  {
    var state = CAtomicsLoad(deferredState, .acquire)
    if !state.isResolved
    {
      let waiter = UnsafeMutablePointer<Waiter<Value>>.allocate(capacity: 1)
      waiter.initialize(to: Waiter(queue, handler))

      if boostQoS, let qos = queue?.qos, qos > self.queue.qos
      { // try to raise `self.queue`'s QoS if the notification needs to execute at a higher QoS
        self.queue.async(qos: qos, flags: [.enforceQoS, .barrier], execute: {})
      }

      repeat {
        waiter.pointee.next = state.waiters?.assumingMemoryBound(to: Waiter<Value>.self)
        let newState = Int(bitPattern: waiter) | state.state
        if CAtomicsCompareAndExchange(deferredState, &state, newState, .weak, .release, .relaxed)
        { // waiter is now enqueued; it will be deallocated at a later time by notifyWaiters()
          return
        }
      } while !state.isResolved

      // this Deferred has become resolved; clean up
      waiter.deinitialize(count: 1)
      waiter.deallocate()
      _ = CAtomicsLoad(deferredState, .acquire)
    }

    // this Deferred is resolved
    let q = queue ?? self.queue
    q.async(execute: { [result = resolved!] in handler(result) })
  }

  /// Query the current state of this `Deferred`
  /// - returns: a `deferredState.pointee` that describes this `Deferred`

  public var state: DeferredState {
    let state = CAtomicsLoad(deferredState, .acquire)
    return state.isResolved ?
      (resolved!.isValue ? .succeeded : .errored) :
      (state.state == .waiting ? .waiting : .executing )
  }

  /// Query whether this `Deferred` has become resolved.
  /// - returns: `true` iff this `Deferred` has become resolved.

  public var isResolved: Bool {
    return CAtomicsLoad(deferredState, .relaxed).isResolved
  }

  /// Attempt to cancel this `Deferred`
  ///
  /// A successful cancellation will result in a `Deferred` equivalent to as if it had been initialized as follows:
  /// ```
  /// Deferred<Value>(error: DeferredError.canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation. Defaults to an empty `String`.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  public final func cancel(_ reason: String = "") -> Bool
  {
    return cancel(.canceled(reason))
  }

  /// Attempt to cancel this `Deferred`
  ///
  /// - parameter error: a `DeferredError` detailing the reason for the attempted cancellation.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  open func cancel(_ error: DeferredError) -> Bool
  {
    return resolve(error: error)
  }

  /// Get this `Deferred`'s `Result`, blocking if necessary until it exists.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s `Result`

  public var result: Result<Value, Error> {
    if CAtomicsLoad(deferredState, .acquire).isResolved == false
    {
      if let current = DispatchQoS.QoSClass.current, current > queue.qos.qosClass
      { // try to boost the QoS class of the running task if it is lower than the current thread's QoS
        queue.async(qos: DispatchQoS(qosClass: current, relativePriority: 0),
                    flags: [.enforceQoS, .barrier], execute: {})
      }
      let s = DispatchSemaphore(value: 0)
      self.notify(boostQoS: false, handler: { _ in s.signal() })
      s.wait()
      _ = CAtomicsLoad(deferredState, .acquire)
    }

    // this Deferred is resolved
    return resolved!
  }

  /// Get this `Deferred`'s value, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with an `Error`, that `Error` is thrown.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved `Value`, or a thrown `Error`

  public func get() throws -> Value
  {
    return try result.get()
  }

  /// Get this `Deferred`'s `Result` if has been resolved, `nil` otherwise.
  ///
  /// This call is non-blocking and wait-free.
  ///
  /// - returns: this `Deferred`'s `Result`, or `nil`

  public func peek() -> Result<Value, Error>?
  {
    if CAtomicsLoad(deferredState, .acquire).isResolved
    {
      return resolved
    }
    return nil
  }

  /// Get this `Deferred`'s value, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with an `Error`, return nil.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved value, or `nil`

  public var value: Value? {
    return result.value
  }

  /// Get this `Deferred`'s error state, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with a `Value`, return nil.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved error state, or `nil`

  public var error: Error? {
    return result.error
  }

  /// Get the QoS of this `Deferred`'s queue
  /// - returns: the QoS of this `Deferred`'s queue

  public var qos: DispatchQoS { return self.queue.qos }
}

public struct Resolver<Value>
{
  private weak var deferred: Deferred<Value>?

  fileprivate init(_ deferred: Deferred<Value>)
  {
    self.deferred = deferred
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
  public func resolve(_ result: Result<Value, Error>) -> Bool
  {
    return deferred?.resolve(result) ?? false
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
  public func resolve(value: Value) -> Bool
  {
    return resolve(Result<Value, Error>(value: value))
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
  public func resolve(error: Error) -> Bool
  {
    return resolve(Result<Value, Error>(error: error))
  }

  /// Attempt to cancel the underlying `Deferred`, and report on whether cancellation happened successfully.
  ///
  /// A successful cancellation will result in a `Deferred` equivalent to as if it had been initialized as follows:
  /// ```
  /// Deferred<Value>(error: DeferredError.canceled(reason))
  /// ```
  ///
  /// - parameter reason: a `String` detailing the reason for the attempted cancellation. Defaults to an empty `String`.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  public func cancel(_ reason: String = "") -> Bool
  {
    return cancel(DeferredError.canceled(reason))
  }

  /// Attempt to cancel the underlying `Deferred`, and report on whether cancellation happened successfully.
  ///
  /// - parameter error: a `DeferredError` detailing the reason for the attempted cancellation.
  /// - returns: whether the cancellation was performed successfully.

  @discardableResult
  public func cancel(_ error: DeferredError) -> Bool
  {
    return resolve(Result<Value, Error>(error: error))
  }

  /// Change the state of the underlying `Deferred` from `.waiting` to `.executing`

  public func beginExecution()
  {
    deferred?.beginExecution()
  }

  /// Query the Quality-of-Service used by this `Resolver`'s underlying `Deferred`

  public var qos: DispatchQoS { return deferred?.queue.qos ?? .unspecified }

  /// Query whether the underlying `Deferred` still exists and is also unresolved

  public var needsResolution: Bool { return deferred?.isResolved == false }

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

/// A `Deferred` to be resolved (`TBD`) manually.

open class TBD<Value>: Deferred<Value>
{
  /// Initialize an unresolved `Deferred`, `TBD`.
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed

  public init(queue: DispatchQueue, task: (Resolver<Value>) -> Void)
  {
    super.init(queue: queue)
    task(Resolver(self))
  }

  /// Initialize an unresolved `Deferred`, `TBD`.
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.

  public init(qos: DispatchQoS = .current, task: (Resolver<Value>) -> Void)
  {
    let queue = DispatchQueue(label: "tbd", qos: qos)
    super.init(queue: queue)
    task(Resolver(self))
  }

  /// Obtain an unresolved `Deferred` with a paired `Resolver`
  ///
  /// - parameter queue: the `DispatchQueue` on which the notifications will be executed

  public static func CreatePair(queue: DispatchQueue) -> (resolver: Resolver<Value>, deferred: Deferred<Value>)
  {
    let d = Deferred<Value>(queue: queue)
    return (Resolver(d), d)
  }

  /// Obtain an unresolved `Deferred` with a paired `Resolver`
  ///
  /// - parameter qos: the QoS at which the notifications should be performed; defaults to the current QoS class.

  public static func CreatePair(qos: DispatchQoS = .current) -> (resolver: Resolver<Value>, deferred: Deferred<Value>)
  {
    let queue = DispatchQueue(label: "tbd", qos: qos)
    return CreatePair(queue: queue)
  }
}
