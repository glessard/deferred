//
//  waiter.swift
//  deferred
//
//  Created by Guillaume Lessard on 2015-07-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

struct Waiter<Success, Failure: Error>
{
  fileprivate let waiter: WaiterType<Success, Failure>
  var next: UnsafeMutablePointer<Waiter<Success, Failure>>? = nil

  init(_ queue: DispatchQueue?, _ handler: @escaping (Result<Success, Failure>) -> Void)
  {
    waiter = .notification(queue, handler)
  }

  init(source: AnyObject)
  {
    waiter = .datasource(source)
  }
}

private enum WaiterType<Success, Failure: Error>
{
  case notification(DispatchQueue?, (Result<Success, Failure>) -> Void)
  case datasource(AnyObject)
}

func notifyWaiters<S, F>(_ queue: DispatchQueue,
                         _ tail: UnsafeMutablePointer<Waiter<S, F>>,
                         _ result: Result<S, F>)
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
        handler(result)
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
          handler(result)
          current.deinitialize(count: 1)
          current.deallocate()
        }
      case .notification(nil, let handler):
        handler(result)
        fallthrough
      case .datasource:
        current.deinitialize(count: 1)
        current.deallocate()
      }
    }
  }
}

func deallocateWaiters<S, F>(_ tail: UnsafeMutablePointer<Waiter<S, F>>?)
{
  var waiter = tail
  while let current = waiter
  {
    waiter = current.pointee.next

    current.deinitialize(count: 1)
    current.deallocate()
  }
}

private func reverseList<S, F>(_ tail: UnsafeMutablePointer<Waiter<S, F>>) -> UnsafeMutablePointer<Waiter<S, F>>?
{
  if tail.pointee.next == nil { return tail }

  var head: UnsafeMutablePointer<Waiter<S, F>>? = nil
  var current = Optional(tail)
  while let element = current
  {
    current = element.pointee.next

    element.pointee.next = head
    head = element
  }
  return head
}
