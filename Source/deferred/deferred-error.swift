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

public enum DeferredError: Error
{
  case canceled(String)
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
    }
  }
}

extension DeferredError: Equatable {}

public func == (a: DeferredError, b: DeferredError) -> Bool
{
  switch (a,b)
  {
  case (.canceled(let ma), .canceled(let mb)): return ma == mb
  }
}
