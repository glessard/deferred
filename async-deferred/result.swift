//
//  Result.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-16.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Foundation

public struct NoResult: ErrorType
{
  private init() {}
}

/// A Result type, approximately like everyone else has done.
///
/// Unlike other implementations, the error case does not encode type beyond ErrorType.
/// This way there is no need to ever map between error types, which is a thing that cannot make sense.

public enum Result<T>: CustomStringConvertible
{
  case Value(T)
  case Error(ErrorType)

  public init()
  {
    self = .Error(NoResult())
  }

  public init(@noescape task: () throws -> T)
  {
    do {
      let value = try task()
      self = .Value(value)
    }
    catch {
      self = .Error(error)
    }
  }


  public var value: T? {
    switch self
    {
    case .Value(let value): return value
    case .Error:            return nil
    }
  }

  public var error: ErrorType? {
    switch self
    {
    case .Value:            return nil
    case .Error(let error): return error
    }
  }

  public func getValue() throws -> T
  {
    switch self
    {
    case .Value(let value): return value
    case .Error(let error): throw error
    }
  }


  public var description: String {
    switch self
    {
    case .Value(let value): return "\(value)"
    case .Error(let error): return "Error: \(error)"
    }
  }


  public func map<U>(transform: (T) throws -> U) -> Result<U>
  {
    switch self
    {
    case .Value(let value): return Result<U> { try transform(value) }
    case .Error(let error): return .Error(error)
    }
  }

  public func flatMap<U>(transform: (T) -> Result<U>) -> Result<U>
  {
    switch self
    {
    case .Value(let value): return transform(value)
    case .Error(let error): return .Error(error)
    }
  }

  public func apply<U>(transform: Result<(T) throws -> U>) -> Result<U>
  {
    switch self
    {
    case .Value(let value):
      switch transform
      {
      case .Value(let transform):
        return Result<U> { try transform(value) }

      case .Error(let error):
        return .Error(error)
      }

    case .Error(let error):
      return .Error(error)
    }
  }
}

public func ?? <T> (possible: Result<T>, @autoclosure alternate: () -> T) -> T
{
  switch possible
  {
  case .Value(let value): return value
  case .Error:            return alternate()
  }
}
