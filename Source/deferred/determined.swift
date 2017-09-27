//
//  determined.swift
//  deferred
//
//  Created by Guillaume Lessard on 9/26/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

public struct Determined<Value>
{
  let result: Result<Value>

  init(_ result: Result<Value>)
  {
    self.result = result
  }

  public func get() throws -> Value
  {
    switch result
    {
    case .value(let value): return value
    case .error(let error): throw error
    }
  }

  public var value: Value? {
    if case .value(let value) = result { return value }
    return nil
  }

  public var error: Error? {
    if case .error(let error) = result { return error }
    return nil
  }

  public var isValue: Bool {
    if case .value = result { return true }
    return false
  }

  public var isError: Bool {
    if case .error = result { return true }
    return false
  }
}
