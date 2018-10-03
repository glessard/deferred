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

public enum DeferredError: Error, Equatable
{
  case canceled(String)
  case invalid(String)
  case timedOut(String)
}

extension DeferredError: CustomStringConvertible
{
  public var description: String {
    switch self
    {
    case .canceled(let message):
      return message.isEmpty ?
        "Deferred was canceled before a result became available" :
        "Deferred canceled: \(message)"
    case .invalid(let message):
      return message.isEmpty ?
        "Deferred failed validation" :
        "Deferred invalid: \(message)"
    case .timedOut(let message):
      return message.isEmpty ?
        "Deferred operation timed out before a result became available" :
        "Deferred operation timed out: \(message)"
    }
  }
}

#if !swift(>=4.1)
public func == (a: DeferredError, b: DeferredError) -> Bool
{
  switch (a,b)
  {
  case (.canceled(let ma), .canceled(let mb)): return ma == mb
  case (.invalid(let ma), .invalid(let mb)):   return ma == mb
  case (.timedOut(let ma), .timedOut(let mb)): return ma == mb
  default:                                     return false
  }
}
#endif
