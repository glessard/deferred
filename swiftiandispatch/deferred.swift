//
//  deferred.swift
//  swiftiandispatch
//
//  Created by Guillaume Lessard on 2015-07-09.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

public enum DeferredState: Int32 { case Waiting = 0, Working = 1, /* Canceled = 2, */ Determined = 3, Assigning = 99 }

public enum DeferredError: ErrorType { case AlreadyDetermined(String), CannotDetermine(String) }

/**
  An asynchronous computation result.

  The `value` property will return the result, blocking until it is ready.
  If the result is ready when `value` is called, it will return immediately.
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
    guard setState(.Working) else { fatalError("Could not start task in \(__FUNCTION__)") }
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

  deinit
  {
    WaitStack.stackDealloc(waiters)
  }

  // MARK: private methods

  private func setState(newState: DeferredState) -> Bool
  {
    switch newState
    {
    case .Waiting:
      return currentState == DeferredState.Waiting.rawValue

    case .Working:
      return OSAtomicCompareAndSwap32Barrier(DeferredState.Waiting.rawValue, DeferredState.Working.rawValue, &currentState)

    // case .Canceled:

    case .Assigning:
      return OSAtomicCompareAndSwap32Barrier(DeferredState.Working.rawValue, DeferredState.Assigning.rawValue, &currentState)

    case .Determined:
      if OSAtomicCompareAndSwap32Barrier(DeferredState.Assigning.rawValue, DeferredState.Determined.rawValue, &currentState)
      {
        while true
        {
          let stack = waiters
          if CAS(stack, nil, &waiters)
          {
            // syncprint(syncread(&waiting))
            // syncprint("Stack is \(stack)")
            WaitStack.stackNotify(stack)
            return true
          }
        }
      }
      return currentState == DeferredState.Determined.rawValue
    }
  }
  
  private func setValue(value: T) throws
  { // A very simple turnstile to ensure only one thread can succeed
    guard setState(.Assigning) else
    {
      if currentState == DeferredState.Determined.rawValue
      {
        throw DeferredError.AlreadyDetermined("Probable attempt to set value of Deferred twice with \(__FUNCTION__)")
      }
      throw DeferredError.CannotDetermine("Deferred in wrong state at start of \(__FUNCTION__)")
    }

    v = value

    guard setState(.Determined) else
    { throw DeferredError.CannotDetermine("Could not complete assignment of value in \(__FUNCTION__)") }

    // The result is now available for the world
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
      while true
      {
        let head = waiters
        waiter.memory.next = head
        if syncread(&currentState) != DeferredState.Determined.rawValue
        {
          if CAS(head, waiter, &waiters)
          {
            // OSAtomicIncrement32Barrier(&waiting)
            let kr = thread_suspend(thread)
            guard kr == KERN_SUCCESS else { fatalError("Thread suspension failed with code \(kr)") }
            break
          }
        }
        else
        { // Deferred has a value now
          waiter.destroy(1)
          waiter.dealloc(1)
          break
        }
      }
    }
    return v
  }

  // private var waiting: Int32 = 0

  public func notify(queue: dispatch_queue_t, task: (T) -> Void)
  {
    let block = { task(self.v) } // This cannot be [weak self]

    if currentState != DeferredState.Determined.rawValue
    {
      let waiter = UnsafeMutablePointer<Waiter>.alloc(1)
      waiter.initialize(Waiter(.Dispatch(queue, block)))
      while true
      {
        let head = waiters
        waiter.memory.next = head
        if syncread(&currentState) != DeferredState.Determined.rawValue
        {
          if CAS(head, waiter, &waiters)
          {
            // OSAtomicIncrement32Barrier(&waiting)
            return
          }
        }
        else
        { // Deferred has a value now
          waiter.destroy(1)
          waiter.dealloc(1)
          break
        }
      }
    }
    dispatch_async(queue, block)
  }
}

public class Determinable<T>: Deferred<T>
{
  override public init() { super.init() }

  public func determine(value: T) throws
  {
    super.setState(.Working)
    try super.setValue(value)
  }

  public func beginWork()
  {
    super.setState(.Working)
  }
}
