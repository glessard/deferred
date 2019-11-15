//
//  deferred-error.swift
//  deferred
//
//  Created by Guillaume Lessard on 19/11/2015.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

public enum Cancellation: Error, Equatable, Hashable
{
  case canceled(String)
  case timedOut(String)
  case notSelected // not selected in a race between multiple deferreds
}

extension Cancellation: CustomStringConvertible
{
  public var description: String {
    switch self
    {
    case .canceled(let message):
      return message.isEmpty ?
        "Deferred was canceled before a result became available" :
        "Deferred canceled: \(message)"
    case .timedOut(let message):
      return message.isEmpty ?
        "Deferred operation timed out before a result became available" :
        "Deferred operation timed out: \(message)"
    case .notSelected:
      return "Deferred was canceled when another got resolved more quickly"
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
