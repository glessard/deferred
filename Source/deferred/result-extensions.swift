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

public protocol ResultWrapper
{
  associatedtype Success
  associatedtype Failure: Error

  var result: Result<Success, Failure> { get }

  func get() throws -> Success

  var value: Success? { get }
  var error: Failure? { get }
}

extension ResultWrapper
{
  /// Get this `Deferred`'s value, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with a `Failure`, return nil.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved value, or `nil`

  public var value: Success? {
    if case .success(let value) = result { return value }
    return nil
  }

  /// Get this `Deferred`'s error state, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with a `Success`, return nil.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved error state, or `nil`

  public var error: Failure? {
    if case .failure(let error) = result { return error }
    return nil
  }

  /// Get this `Deferred`'s value, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with a `Failure`, that `Failure` is thrown.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved `Success`, or throws
  /// - throws: this `Deferred`'s resolved `Failure` if it cannot return a `Success`

  public func get() throws -> Success
  {
    return try result.get()
  }
}

extension ResultWrapper where Failure == Never
{
  /// Get this `Deferred`'s value, blocking if necessary until it becomes resolved.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved `Success` value

  public var value: Success {
    switch result
    {
    case .success(let value): return value
    }
  }

  /// Get this `Deferred`'s value, blocking if necessary until it becomes resolved.
  ///
  /// If the `Deferred` is resolved with a `Failure`, that `Failure` is thrown.
  ///
  /// When called on a `Deferred` that is already resolved, this call is non-blocking.
  ///
  /// When called on a `Deferred` that is not resolved, this call blocks the executing thread.
  ///
  /// - returns: this `Deferred`'s resolved `Success`, or throws
  /// - throws: this `Deferred`'s resolved `Failure` if it cannot return a `Success`

  public func get() -> Success
  {
    return value
  }
}
