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

public enum DeferredError: ErrorProtocol
{
  case canceled(String)
  case alreadyDetermined(String)
}

extension DeferredError: CustomStringConvertible
{
  public var description: String {
    switch self
    {
    case .canceled(let message):
      guard message != ""
        else { return "Deferred was canceled before result became available" }
      return "Deferred canceled: \(message)"

    case .alreadyDetermined(let message):
      return "Deferred already determined: \(message)"
    }
  }
}

extension DeferredError: Equatable {}

public func == (a: DeferredError, b: DeferredError) -> Bool
{
  switch (a,b)
  {
  case let (.canceled(ma), .canceled(mb)):                   return ma == mb
  case let (.alreadyDetermined(ma), .alreadyDetermined(mb)): return ma == mb
  default: return false
  }
}
