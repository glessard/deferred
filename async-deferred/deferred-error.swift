//
//  deferred-error.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 19/11/2015.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

/// Error type that can be thrown by a `Deferred`.
///
/// Must be a top-level type because Deferred is generic.

public enum DeferredError: ErrorType
{
  case Canceled(String)
  case AlreadyDetermined(String)
}

extension DeferredError: CustomStringConvertible
{
  public var description: String {
    switch self
    {
    case Canceled(let message):
      guard message != ""
        else { return "Deferred was canceled before result became available" }
      return "Deferred canceled: \(message)"

    case AlreadyDetermined(let message):
      return "Deferred already determined: \(message)"
    }
  }
}

extension DeferredError: Equatable {}

public func == (a: DeferredError, b: DeferredError) -> Bool
{
  switch (a,b)
  {
  case let (.Canceled(ma), .Canceled(mb)):                   return ma == mb
  case let (.AlreadyDetermined(ma), .AlreadyDetermined(mb)): return ma == mb
  default: return false
  }
}
