//
//  waiter.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

#if !compiler(>=5.0)
import Outcome
#endif

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
  var head = reverseList(tail)
  while let current = head
  {
    guard let queue = current.pointee.queue else { break }

    head = current.pointee.next
    // run on the requested queue
    queue.async {
      current.pointee.handler(value)
      current.deinitialize(count: 1)
      current.deallocate()
    }
  }

  if head == nil { return }

  queue.async {
    var head = head
    while let current = head
    {
      head = current.pointee.next

      if let queue = current.pointee.queue
      { // run on the requested queue
        queue.async {
          current.pointee.handler(value)
          current.deinitialize(count: 1)
          current.deallocate()
        }
      }
      else
      { // run on the queue of the just-determined deferred
        current.pointee.handler(value)
        current.deinitialize(count: 1)
        current.deallocate()
      }
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
    current.deallocate()
  }
}

private func reverseList<T>(_ tail: UnsafeMutablePointer<Waiter<T>>?) -> UnsafeMutablePointer<Waiter<T>>?
{
  if tail?.pointee.next == nil { return tail }

  var head: UnsafeMutablePointer<Waiter<T>>? = nil
  var current = tail
  while let element = current
  {
    current = element.pointee.next

    element.pointee.next = head
    head = element
  }
  return head
}
