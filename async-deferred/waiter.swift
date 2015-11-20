//
//  waiter.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

struct Waiter
{
  let block: dispatch_block_t
  var next: UnsafeMutablePointer<Waiter> = nil

  init(_ block: dispatch_block_t)
  {
    self.block = block
  }
}

struct WaitQueue
{
  static func notifyAll(queue: dispatch_queue_t, _ tail: UnsafeMutablePointer<Waiter>)
  {
    var head = reverseList(tail)
    while head != nil
    {
      let current = head
      head = head.memory.next

      dispatch_async(queue, current.memory.block)

      current.destroy()
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

      current.destroy()
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
