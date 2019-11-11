//
//  outcome.swift
//  deferred
//
//  Created by Guillaume Lessard on 9/19/18.
//

#if compiler(>=5.0)

extension Result where Failure == Swift.Error
{
  init(value: Success)
  {
    self = .success(value)
  }

  init(error: Error)
  {
    self = .failure(error)
  }

  var value: Success? {
    if case .success(let value) = self { return value }
    return nil
  }

  var error: Error? {
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
}

#else

import Outcome

public typealias Result<Success, Error> = Outcome<Success>

@available(*, deprecated, renamed: "Outcome")
public typealias Determined = Outcome

#endif
