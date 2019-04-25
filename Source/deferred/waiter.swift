//
//  waiter.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

struct Waiter<T>
{
  fileprivate let waiter: WaiterType<T>
  var next: UnsafeMutablePointer<Waiter<T>>? = nil

  init(_ queue: DispatchQueue?, _ handler: @escaping (Result<T, Error>) -> Void)
  {
    waiter = .notification(queue, handler)
  }

  init(source: AnyObject)
  {
    waiter = .datasource(source)
  }
}

private enum WaiterType<T>
{
  case notification(DispatchQueue?, (Result<T, Error>) -> Void)
  case datasource(AnyObject)
}

func notifyWaiters<T>(_ queue: DispatchQueue, _ tail: UnsafeMutablePointer<Waiter<T>>?, _ value: Result<T, Error>)
{
  var head = reverseList(tail)
  loop: while let current = head
  {
    switch current.pointee.waiter
    {
    case .notification(nil, _):
      break loop
    case .notification(let queue?, let handler):
      head = current.pointee.next
      // execute handler on the requested queue
      queue.async {
        handler(value)
        current.deinitialize(count: 1)
        current.deallocate()
      }
    case .datasource:
      head = current.pointee.next
      current.deinitialize(count: 1)
      current.deallocate()
    }
  }

  if head == nil { return }

  // continue running on the queue of the just-resolved deferred
  queue.async {
    var head = head
    while let current = head
    {
      head = current.pointee.next

      switch current.pointee.waiter
      {
      case .notification(let queue?, let handler):
        // execute handler on the requested queue
        queue.async {
          handler(value)
          current.deinitialize(count: 1)
          current.deallocate()
        }
      case .notification(nil, let handler):
        handler(value)
        fallthrough
      case .datasource:
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
