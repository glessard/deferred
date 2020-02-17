//
//  result-extensions.swift
//  deferred
//

extension Result
{
  /// Map this `Result`'s `Failure` type to `Error` (any Error).

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
  /// Set this `Result`'s `Failure` type to `NewError`
  ///
  /// - parameter to: the type of `Failure` to be used for the returned `Result`
  /// - returns: a `Result` where the `Failure` type is unconditionally converted to `NewError`

  func setFailureType<NewError: Error>(to: NewError.Type) -> Result<Success, NewError>
  {
    switch self
    {
    case .success(let value): return Result<Success, NewError>.success(value)
    }
  }
}

/// A representation for a type that always contains a `Result`

public protocol ResultWrapper
{
  associatedtype Success
  associatedtype Failure: Error

  /// The wrapped `Result`
  ///
  /// `result` must be implemented in order to conform to `ResultWrapper`.
  /// Its performance characteristics will be inherited by the default implementations.
  var result: Result<Success, Failure> { get }

  /// Obtain the wrapped `Success` case, or throw the `Failure`
  ///
  /// - returns: the `Success` value, if this `Result` represents a `Success`
  /// - throws:  the `Failure` value, if this `Result` represents a `Failure`
  func get() throws -> Success

  /// Obtain the `Success` value if the wrapped `Result` is a `Success`, or return `nil`
  var value: Success? { get }

  /// Obtain the `Failure` value if the wrapped `Result` is a `Failure`, or return `nil`
  var error: Failure? { get }
}

extension ResultWrapper
{
  /// Obtain the `Success` value if the wrapped `Result` is a `Success`, or return `nil`
  ///
  /// The default implementation uses the `result` computed property,
  /// and therefore inherits its performance characteristics.

  public var value: Success? {
    if case .success(let value) = result { return value }
    return nil
  }

  /// Obtain the `Failure` value if the wrapped `Result` is a `Failure`, or return `nil`
  ///
  /// The default implementation uses the `result` computed property,
  /// and therefore inherits its performance characteristics.

  public var error: Failure? {
    if case .failure(let error) = result { return error }
    return nil
  }

  /// Obtain the `Success` value if the wrapped `Result` is a `Success`, or throw the `Failure`.
  ///
  /// The default implementation uses the `result` computed property,
  /// and therefore inherits its performance characteristics.
  ///
  /// - returns: this `ResultWrapper`'s `Success` value, or throws
  /// - throws: this `ResultWrapper`'s `Failure` value if it cannot return a `Success`

  public func get() throws -> Success
  {
    return try result.get()
  }
}

extension ResultWrapper where Failure == Never
{
  /// Obtain the `Success` value of the wrapped `Result`
  ///
  /// The default implementation uses the `result` computed property,
  /// and therefore inherits its performance characteristics.

  public var value: Success {
    switch result
    {
    case .success(let value): return value
    }
  }

  /// Obtain the `Success` value of the wrapped `Result`.
  ///
  /// The default implementation uses the `result` computed property,
  /// and therefore inherits its performance characteristics.
  ///
  /// - returns: this `ResultWrapper`'s `Success` value

  public func get() -> Success
  {
    return value
  }
}
