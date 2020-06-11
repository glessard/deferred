//
//  deferred-error.swift
//  deferred
//
//  Created by Guillaume Lessard on 19/11/2015.
//  Copyright © 2015-2020 Guillaume Lessard. All rights reserved.
//

public enum Cancellation: Error, Equatable, Hashable
{
#if compiler(>=5.1)
  case canceled(String = "")
  case timedOut(String = "")
#else
  case canceled(String)
  case timedOut(String)

  public static func canceled() -> Cancellation { return .canceled("") }
  public static func timedOut() -> Cancellation { return .timedOut("") }
#endif
}

extension Cancellation: CustomStringConvertible
{
  public var description: String {
    switch self
    {
    case .canceled(let message):
      return message.isEmpty ?
        "canceled" : "canceled: \(message)"
    case .timedOut(let message):
      return message.isEmpty ?
        "timed out" : "timed out: \(message)"
    }
  }
}

public enum Invalidation: Error, Equatable, Hashable
{
  case invalid(String)
}

extension Invalidation: CustomStringConvertible
{
  public var description: String {
    switch self
    {
    case .invalid(let message):
      return message.isEmpty ?
        "Deferred failed validation" :
        "Deferred invalid: \(message)"
    }
  }
}
