//
//  deferred.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-09.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  The possible states of a `Deferred`.

  Must be a top-level type because Deferred is generic.
*/

public enum DeferredState: Int32 { case Waiting = 0, Executing = 1, Determined = 2 }
private let transientState = Int32.max

/**
  These errors can be thrown by a `Deferred`.

  Must be a top-level type because Deferred is generic.
*/

public enum DeferredError: ErrorType
{
  case AlreadyDetermined(String)
  case CannotDetermine(String)
}

/**
  An asynchronous computation.

  A `Deferred` starts out undetermined, in the `.Waiting` state.
  It may then enter the `.Executing` state, and will eventually become `.Determined`.
  Once it is `.Determined`, it is ready to supply a result.

  The `value` property will return the result, blocking until it becomes determined.
  If the result is ready when `value` is called, it will return immediately.

  A closure supplied to the `notify` method will be called after the `Deferred` has become determined.
*/

public class Deferred<T>
{
  private var v: T! = nil

  private var currentState: Int32 = DeferredState.Waiting.rawValue
  private var waiters = UnsafeMutablePointer<Waiter>(nil)

  // MARK: Initializers

  private init() {}

  public init(value: T)
  {
    v = value
    currentState = DeferredState.Determined.rawValue
  }

  public init(queue: dispatch_queue_t, task: () -> T)
  {
    currentState = DeferredState.Executing.rawValue
    dispatch_async(queue) {
      try! self.setValue(task())
    }
  }

  public convenience init(qos: qos_class_t, task: () -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos, 0), task: task)
  }

  public convenience init(_ task: () -> T)
  {
    self.init(queue: dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  // constructor used by `map`

  public convenience init<U>(queue: dispatch_queue_t, source: Deferred<U>, transform: (U) -> T)
  {
    self.init()

    source.notify(queue) {
      value in
      self.beginExecution()
      try! self.setValue(transform(value))
    }
  }

  // constructor used by `flatMap`

  public convenience init<U>(queue: dispatch_queue_t, source: Deferred<U>, transform: (U) -> Deferred<T>)
  {
    self.init()

    source.notify(queue) {
      value in
      self.beginExecution()
      transform(value).notify { transformedValue in try! self.setValue(transformedValue) }
    }
  }

  // constructor used by `apply`

  public convenience init<U>(queue: dispatch_queue_t, source: Deferred<U>, transform: Deferred<(U) -> T>)
  {
    self.init()

    source.notify(queue) {
      value in
      transform.notify(queue) {
        transform in
        self.beginExecution()
        try! self.setValue(transform(value))
      }
    }
  }

  // constructor used by `delay`

  public convenience init(queue: dispatch_queue_t, source: Deferred, delay: dispatch_time_t)
  {
    self.init()

    source.notify(queue) {
      value in
      self.beginExecution()
      dispatch_after(delay, queue) {
        try! self.setValue(value)
      }
    }
  }

  deinit
  {
    WaitQueue.dealloc(waiters)
  }

  // MARK: private methods

  private func beginExecution()
  {
    OSAtomicCompareAndSwap32Barrier(DeferredState.Waiting.rawValue, DeferredState.Executing.rawValue, &currentState)
  }

  private func setValue(value: T) throws
  {
    // A turnstile to ensure only one thread can succeed
    while true
    { // Allow multiple tries in case another thread concurrently switches state from .Waiting to .Executing
      let initialState = currentState
      if initialState < DeferredState.Determined.rawValue
      {
        guard OSAtomicCompareAndSwap32Barrier(initialState, transientState, &currentState) else { continue }
        break
      }
      else
      {
        assert(currentState >= DeferredState.Determined.rawValue)
        throw DeferredError.AlreadyDetermined("Attempted to determine Deferred twice with \(__FUNCTION__)")
      }
    }

    v = value

    guard OSAtomicCompareAndSwap32Barrier(transientState, DeferredState.Determined.rawValue, &currentState) else
    { // Getting here seems impossible, but try to handle it gracefully.
      throw DeferredError.CannotDetermine("Failed to determine Deferred")
    }

    while true
    {
      let queue = waiters
      if CAS(queue, nil, &waiters)
      {
        // syncprint(syncread(&waiting))
        // syncprint("Queue tail is \(queue)")
        WaitQueue.notifyAll(queue)
        break
      }
    }
    // The result is now available for the world
  }

  // private var waiting: Int32 = 0

  private func enqueue(waiter: UnsafeMutablePointer<Waiter>) -> Bool
  {
    while true
    {
      let tail = waiters
      waiter.memory.next = tail
      if syncread(&currentState) != DeferredState.Determined.rawValue
      {
        if CAS(tail, waiter, &waiters)
        { // waiter is now enqueued
          // OSAtomicIncrement32Barrier(&waiting)
          return true
        }
      }
      else
      { // This Deferred has become determined; bail
        return false
      }
    }
  }

  // MARK: public interface

  public var state: DeferredState { return DeferredState(rawValue: currentState)! }

  public var isDetermined: Bool { return currentState == DeferredState.Determined.rawValue }

  public func peek() -> T?
  {
    if currentState != DeferredState.Determined.rawValue
    {
      return nil
    }
    return v
  }

  public var value: T {
    if currentState != DeferredState.Determined.rawValue
    {
      let thread = mach_thread_self()
      let waiter = UnsafeMutablePointer<Waiter>.alloc(1)
      waiter.initialize(Waiter(.Thread(thread)))

      if enqueue(waiter)
      { // waiter will be deallocated after the thread is woken
        let kr = thread_suspend(thread)
        guard kr == KERN_SUCCESS else { fatalError("Thread suspension failed with code \(kr)") }
      }
      else
      {
        waiter.destroy(1)
        waiter.dealloc(1)
      }
    }

    return v
  }

  public func notify(queue: dispatch_queue_t, task: (T) -> Void)
  {
    let block = { task(self.v) } // This cannot be [weak self]

    if currentState != DeferredState.Determined.rawValue
    {
      let waiter = UnsafeMutablePointer<Waiter>.alloc(1)
      waiter.initialize(Waiter(.Closure(queue, block)))

      if enqueue(waiter)
      { // waiter will be deallocated after the block is dispatched to GCD
        return
      }
      else
      { // Deferred has a value now
        waiter.destroy(1)
        waiter.dealloc(1)
      }
    }

    dispatch_async(queue, block)
  }
}

/**
  A Deferred to be determined (TBD) manually.
*/

public class TBD<T>: Deferred<T>
{
  override public init() { super.init() }

  public func determine(value: T) throws
  {
    try super.setValue(value)
  }

  public override func beginExecution()
  {
    super.beginExecution()
  }
}
