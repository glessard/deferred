//
//  outcome.swift
//  deferred
//
//  Created by Guillaume Lessard on 9/19/18.
//

#if compiler(>=5.0)

public typealias Outcome<Value> = Swift.Result<Value, Swift.Error>

extension Result where Failure == Swift.Error
{
  @inlinable
  public init(value: Success)
  {
    self = .success(value)
  }

  @inlinable
  public init(error: Error)
  {
    self = .failure(error)
  }

  @inlinable
  public var value: Success? {
    if case .success(let value) = self { return value }
    return nil
  }

  @inlinable
  public var error: Error? {
    if case .failure(let error) = self { return error }
    return nil
  }

  @inlinable
  public var isValue: Bool {
    if case .success = self { return true }
    return false
  }

  @inlinable
  public var isError: Bool {
    if case .failure = self { return true }
    return false
  }
}

#else

import Outcome

@available(*, deprecated, renamed: "Outcome")
public typealias Determined = Outcome

#endif
