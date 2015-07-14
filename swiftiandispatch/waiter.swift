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
    case Dispatch(dispatch_queue_t, () -> Void)
    case Thread(thread_t)
  }

  let waiter: Type
  var next = UnsafeMutablePointer<Waiter>(nil)

  init(_ t: Type)
  {
    waiter = t
  }

  func wake()
  {
    switch waiter
    {
    case .Dispatch(let queue, let task):
      dispatch_async(queue, task)

    case .Thread(let thread):
      while case let kr = thread_resume(thread) where kr != KERN_SUCCESS
      {
        guard kr == KERN_FAILURE else { preconditionFailure("Thread resumption failed with code \(kr)") }
        // thread wasn't suspended yet
      }
    }
  }
}

extension Waiter
{
  static func stackNotify(waiter: UnsafeMutablePointer<Waiter>)
  {
    if waiter != nil
    {
      stackNotify(waiter.memory.next)
      waiter.memory.wake()
      waiter.destroy(1)
      waiter.dealloc(1)
    }
  }

  static func stackDealloc(waiter: UnsafeMutablePointer<Waiter>)
  {
    if waiter != nil
    {
      stackDealloc(waiter)
      waiter.destroy(1)
      waiter.dealloc(1)
    }
  }
}

@inline(__always) func CAS<T>(o: UnsafeMutablePointer<T>, _ n: UnsafeMutablePointer<T>,
                              _ p: UnsafeMutablePointer<UnsafeMutablePointer<T>>) -> Bool
{
  return OSAtomicCompareAndSwapPtrBarrier(o, n, UnsafeMutablePointer(p))
}
