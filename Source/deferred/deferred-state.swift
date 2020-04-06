//
//  deferred-state.swift
//  deferred
//
//  Created by Guillaume Lessard on 2020-04-15
//  Copyright © 2020 Guillaume Lessard. All rights reserved.
//

import Foundation
import protocol SwiftCompatibleAtomics.AtomicValue

/// The possible states of a `Deferred`.
///
/// Must be a top-level type because Deferred is generic.

public enum DeferredState: Int, Equatable, Hashable
{
  case waiting = 0x0, executing = 0x1, resolved = 0x3
}

// All the bits required to express a `DeferredState`'s `rawValue`

private let stateMask = 0x3

/// A type-preserving container for the task that defines a `Deferred`

struct DeferredTask<Success, Failure: Error>
{
  let task: (Resolver<Success, Failure>) -> Void
}

/// Express the internal state of a `Deferred`

struct InternalState: AtomicValue, RawRepresentable
{
  var rawValue: Int

  init(rawValue: Int)
  {
    self.rawValue = rawValue
  }

  init(state: DeferredState)
  {
    rawValue = state.rawValue & stateMask
  }

  private init(_ pointer: UnsafeMutableRawPointer, state: DeferredState)
  {
    rawValue = Int(bitPattern: pointer) | (state.rawValue & stateMask)
  }

  init<Success, Failure>(resolved: UnsafeMutablePointer<Result<Success, Failure>>)
  {
    self.init(resolved, state: .resolved)
  }

  init<Success, Failure>(task: UnsafeMutablePointer<DeferredTask<Success, Failure>>)
  {
    self.init(task, state: .waiting)
  }

  init<Success, Failure>(waiter: UnsafeMutablePointer<Waiter<Success, Failure>>)
  {
    self.init(waiter, state: .executing)
  }

  var state: DeferredState { return DeferredState(rawValue: rawValue & stateMask)! }
  private var pointer: UnsafeMutableRawPointer? { return UnsafeMutableRawPointer(bitPattern: rawValue & ~stateMask) }

  /// Get a pointer to a `DeferredTask` that will resolve this `Deferred`

  func deferredTask<Success, Failure>(for deferred: Deferred<Success, Failure>.Type) -> UnsafeMutablePointer<DeferredTask<Success, Failure>>?
  {
    guard state == .waiting else { return nil }
    return pointer?.assumingMemoryBound(to: DeferredTask<Success, Failure>.self)
  }

  /// Get a pointer to the first `Waiter` for an unresolved `Deferred`.
  /// `self` must have been read with `.acquire` memory ordering in order
  /// to safely see all the changes from the thread that last enqueued a `Waiter`.

  func waiterQueue<Success, Failure>(for deferred: Deferred<Success, Failure>.Type) -> UnsafeMutablePointer<Waiter<Success, Failure>>?
  {
    guard state == .executing else { return nil }
    return pointer?.assumingMemoryBound(to: Waiter<Success, Failure>.self)
  }

  /// Get a pointer to a `Result` for a resolved `Deferred`.
  /// `self` must have been read with `.acquire` memory ordering in order
  /// to safely see all the changes from the thread that resolved this `Deferred`.

  func resolution<Success, Failure>(for deferred: Deferred<Success, Failure>.Type) -> UnsafeMutablePointer<Result<Success, Failure>>?
  {
    guard state == .resolved else { return nil }
    return pointer?.assumingMemoryBound(to: Result<Success, Failure>.self)
  }
}
