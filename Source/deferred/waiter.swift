//
//  waiter.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch
import Outcome

struct Waiter<T>
{
  fileprivate let queue: DispatchQueue?
  fileprivate let handler: (Outcome<T>) -> Void
  var next: UnsafeMutablePointer<Waiter<T>>? = nil

  init(_ queue: DispatchQueue?, _ handler: @escaping (Outcome<T>) -> Void)
  {
    self.queue = queue
    self.handler = handler
  }
}

func notifyWaiters<T>(_ queue: DispatchQueue, _ tail: UnsafeMutablePointer<Waiter<T>>?, _ value: Outcome<T>)
{
  let (normal, custom) = reverseAndSplitList(tail)

  queue.async {
    var head = normal
    while let current = head
    {
      head = current.pointee.next

      assert(current.pointee.queue == nil)
      current.pointee.handler(value)

      current.deinitialize(count: 1)
#if swift(>=4.1)
      current.deallocate()
#else
      current.deallocate(capacity: 1)
#endif
    }
  }

  var head = custom
  while let current = head
  {
    head = current.pointee.next

    assert(current.pointee.queue != nil)
    current.pointee.queue!.async {
      current.pointee.handler(value)

      current.deinitialize(count: 1)
#if swift(>=4.1)
      current.deallocate()
#else
      current.deallocate(capacity: 1)
#endif
    }
  }
}

func deallocateWaiters<T>(_ tail: UnsafeMutablePointer<Waiter<T>>?)
{
  var waiter = tail
  while let current = waiter
  {
    waiter = current.pointee.next

    current.deinitialize(count: 1)
#if swift(>=4.1)
    current.deallocate()
#else
    current.deallocate(capacity: 1)
#endif
  }
}

private func reverseAndSplitList<T>(_ tail: UnsafeMutablePointer<Waiter<T>>?) -> (UnsafeMutablePointer<Waiter<T>>?, UnsafeMutablePointer<Waiter<T>>?)
{
  if tail?.pointee.next == nil
  {
    if tail?.pointee.queue == nil
    { return (tail, nil) }
    else
    { return (nil, tail) }
  }

  var normal: UnsafeMutablePointer<Waiter<T>>? = nil
  var custom: UnsafeMutablePointer<Waiter<T>>? = nil
  var current = tail
  while let element = current
  {
    current = element.pointee.next

    if element.pointee.queue == nil
    {
      element.pointee.next = normal
      normal = element
    }
    else
    {
      element.pointee.next = custom
      custom = element
    }
  }
  return (normal, custom)
}
