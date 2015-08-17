//
//  waiter.swift
//  swiftiandispatch
//
//  Created by Guillaume Lessard on 2015-07-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

struct Waiter
{
  enum Type
  {
    case Closure(dispatch_queue_t, () -> Void)
    case Thread(thread_t)
  }

  let waiter: Type
  var next: UnsafeMutablePointer<Waiter> = nil

  init(_ t: Type)
  {
    waiter = t
  }

  func wake()
  {
    switch waiter
    {
    case .Closure(let queue, let task):
      dispatch_async(queue, task)

    case .Thread(let thread):
      while case let kr = thread_resume(thread) where kr != KERN_SUCCESS
      {
        guard kr == KERN_FAILURE else { fatalError("thread_resume() failed with code \(kr)") }
        // thread wasn't suspended yet
      }
    }
  }
}

struct WaitQueue
{
  static func notifyAll(tail: UnsafeMutablePointer<Waiter>)
  {
    var head = reverseList(tail)
    while head != nil
    {
      let current = head
      head = head.memory.next

      current.memory.wake()
      current.destroy(1)
      current.dealloc(1)
    }
  }

  static func dealloc(tail: UnsafeMutablePointer<Waiter>)
  {
    var waiter = tail
    while waiter != nil
    {
      let current = waiter
      waiter = waiter.memory.next

      current.destroy(1)
      current.dealloc(1)
    }
  }

  private static func reverseList(var tail: UnsafeMutablePointer<Waiter>) -> UnsafeMutablePointer<Waiter>
  {
    var head: UnsafeMutablePointer<Waiter> = nil
    while tail != nil
    {
      let element = tail
      tail = element.memory.next

      element.memory.next = head
      head = element
    }
    return head
  }
}

@inline(__always) func CAS<T>(o: UnsafeMutablePointer<T>, _ n: UnsafeMutablePointer<T>,
                              _ p: UnsafeMutablePointer<UnsafeMutablePointer<T>>) -> Bool
{
  return OSAtomicCompareAndSwapPtrBarrier(o, n, UnsafeMutablePointer(p))
}

@inline(__always) func syncread(p: UnsafeMutablePointer<Int32>) -> Int32
{
  return OSAtomicAdd32Barrier(0, p)
}

@inline(__always) func syncread<T>(p: UnsafeMutablePointer<UnsafeMutablePointer<T>>) -> UnsafeMutablePointer<T>
{
  #if arch(x86_64) || arch(arm64)
    return UnsafeMutablePointer(bitPattern: Int(OSAtomicAdd64Barrier(0, UnsafeMutablePointer<Int64>(p))))
  #else
    return UnsafeMutablePointer(bitPattern: Int(OSAtomicAdd32Barrier(0, UnsafeMutablePointer<Int32>(p))))
  #endif
}
