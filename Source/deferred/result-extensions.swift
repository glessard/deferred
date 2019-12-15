//
//  result-extensions.swift
//  deferred
//

extension Result
{
  var withAnyError: Result<Success, Error> {
    switch self
    {
    case .success(let value): return Result<Success, Error>.success(value)
    case .failure(let error): return Result<Success, Error>.failure(error)
    }
  }
}

extension Result where Failure == Never
{
  func setFailureType<E: Error>(to: E.Type) -> Result<Success, E>
  {
    switch self
    {
    case .success(let value): return Result<Success, E>.success(value)
    }
  }
}
