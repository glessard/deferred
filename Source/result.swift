//
//  Result.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-16.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Foundation.NSError

public struct NoResult: ErrorType, CustomStringConvertible
{
  private init() {}
  public var description = "No result"
}

/// A Result type, approximately like everyone else has done.
///
/// The error case does not encode type beyond ErrorType.
/// This way there is no need to ever map between error types, which mostly cannot make sense.

public enum Result<Value>: CustomStringConvertible
{
  case value(Value)
  case error(ErrorType)

  public init()
  {
    self = .error(NoResult())
  }

  public init(@noescape task: () throws -> Value)
  {
    do {
      let value = try task()
      self = .value(value)
    }
    catch {
      self = .error(error)
    }
  }

  public func asValue() -> Value?
  {
    switch self
    {
    case .value(let value): return value
    case .error:            return nil
    }
  }

  public var isValue: Bool {
    switch self
    {
    case .value: return true
    case .error: return false
    }
  }

  public func asError() -> ErrorType?
  {
    switch self
    {
    case .value:            return nil
    case .error(let error): return error
    }
  }

  public var isError: Bool {
    switch self
    {
    case .value: return false
    case .error: return true
    }
  }

  public func getValue() throws -> Value
  {
    switch self
    {
    case .value(let value): return value
    case .error(let error): throw error
    }
  }


  public var description: String {
    switch self
    {
    case .value(let value): return String(value)
    case .error(let error): return "Error: \(error)"
    }
  }


  public func map<Other>(@noescape transform: (Value) throws -> Other) -> Result<Other>
  {
    switch self
    {
    case .value(let value): return Result<Other> { try transform(value) }
    case .error(let error): return .error(error)
    }
  }

  public func flatMap<Other>(@noescape transform: (Value) -> Result<Other>) -> Result<Other>
  {
    switch self
    {
    case .value(let value): return transform(value)
    case .error(let error): return .error(error)
    }
  }

  public func apply<Other>(transform: Result<(Value) throws -> Other>) -> Result<Other>
  {
    switch self
    {
    case .value(let value):
      switch transform
      {
      case .value(let transform): return Result<Other> { try transform(value) }
      case .error(let error):     return .error(error)
      }

    case .error(let error):       return .error(error)
    }
  }

  public func apply<Other>(transform: Result<(Value) -> Result<Other>>) -> Result<Other>
  {
    switch self
    {
    case .value(let value):
      switch transform
      {
      case .value(let transform): return transform(value)
      case .error(let error):     return .error(error)
      }

    case .error(let error):       return .error(error)
    }
  }

  public func recover(@noescape transform: (ErrorType) -> Result<Value>) -> Result<Value>
  {
    switch self
    {
    case .value:            return self
    case .error(let error): return transform(error)
    }
  }
}

public func ?? <Value> (possible: Result<Value>, @autoclosure alternate: () -> Value) -> Value
{
  switch possible
  {
  case .value(let value): return value
  case .error:            return alternate()
  }
}

public func == <Value: Equatable> (lhr: Result<Value>, rhr: Result<Value>) -> Bool
{
  switch (lhr, rhr)
  {
  case (.value(let lv), .value(let rv)):
    return lv == rv

  case (.error(let le as NSError), .error(let re as NSError)):
    // Use NSObject's equality method, and assume the result to be correct.
    return le.isEqual(re)

  default: return false
  }
}

public func != <Value: Equatable> (lhr: Result<Value>, rhr: Result<Value>) -> Bool
{
  return !(lhr == rhr)
}

public func == <C: CollectionType, Value: Equatable where C.Generator.Element == Result<Value>> (lha: C, rha: C) -> Bool
{
  guard lha.count == rha.count else { return false }

  for (le, re) in zip(lha, rha)
  {
    guard le == re else { return false }
  }

  return true
}

public func != <C: CollectionType, Value: Equatable where C.Generator.Element == Result<Value>> (lha: C, rha: C) -> Bool
{
  return !(lha == rha)
}
