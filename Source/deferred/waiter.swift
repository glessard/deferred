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
  private let queue: DispatchQueue?
  private let handler: (Outcome<T>) -> Void
  var next: UnsafeMutablePointer<Waiter<T>>? = nil

  init(_ queue: DispatchQueue?, _ handler: @escaping (Outcome<T>) -> Void)
  {
    self.queue = queue
    self.handler = handler
  }

  fileprivate func notify(_ queue: DispatchQueue, _ value: Outcome<T>)
  {
    let q = self.queue ?? queue
    q.async { [handler = self.handler] in handler(value) }
  }
}

func notifyWaiters<T>(_ queue: DispatchQueue, _ tail: UnsafeMutablePointer<Waiter<T>>?, _ value: Outcome<T>)
{
  var head = reverseList(tail)
  while let current = head
  {
    head = current.pointee.next

    current.pointee.notify(queue, value)

    current.deinitialize(count: 1)
    current.deallocate()
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

#if !swift(>=4.1)
extension UnsafeMutablePointer
{
  internal func deallocate()
  {
    deallocate(capacity: 1)
  }
}
#endif
