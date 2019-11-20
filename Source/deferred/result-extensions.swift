//
//  outcome.swift
//  deferred
//
//  Created by Guillaume Lessard on 9/19/18.
//

extension Result
{
  init(value: Success)
  {
    self = .success(value)
  }

  init(error: Failure)
  {
    self = .failure(error)
  }

  var value: Success? {
    if case .success(let value) = self { return value }
    return nil
  }

  var error: Failure? {
    if case .failure(let error) = self { return error }
    return nil
  }

  var isValue: Bool {
    if case .success = self { return true }
    return false
  }

  var isError: Bool {
    if case .failure = self { return true }
    return false
  }

  var withAnyError: Result<Success, Error> {
    switch self
    {
    case .success(let value): return Result<Success, Error>(value: value)
    case .failure(let error): return Result<Success, Error>(error: error)
    }
  }
}
