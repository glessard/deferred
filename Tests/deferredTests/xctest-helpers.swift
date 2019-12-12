//
//  xctest-helpers.swift
//

import XCTest

func XCTAssertEqual<E: Error & Equatable>(_ error: Error?, _ target: E,
                                          _ message: @autoclosure () -> String = "",
                                          file: StaticString = #file, line: UInt = #line)
{
  if let e = error as? E
  {
    XCTAssertEqual(e, target, message(), file: file, line: line)
  }
  else
  {
    let d = error.map(String.init(describing:))
    XCTAssertEqual(d, String(describing: target), message(), file: file, line: line)
  }
}

func XCTAssertEqual<Success: Equatable, Failure: Error>(_ result: Result<Success, Failure>?, _ value: Success,
                                                        _ message: @autoclosure () -> String = "",
                                                        file: StaticString = #file, line: UInt = #line)
{
  if case .success(let v)? = result
  {
    XCTAssertEqual(v, value, message(), file: file, line: line)
  }
  else
  {
    XCTAssertEqual(nil, value, message(), file: file, line: line)
  }
}

func XCTAssertEqual<Success, Failure: Error & Equatable>(_ result: Result<Success, Failure>?, _ error: Failure,
                                                         _ message: @autoclosure () -> String = "",
                                                         file: StaticString = #file, line: UInt = #line)
{
  if case .failure(let e)? = result
  {
    XCTAssertEqual(e, error, message(), file: file, line: line)
  }
  else
  {
    XCTAssertEqual(nil, error, message(), file: file, line: line)
  }
}

func XCTAssertEqual<Success, Failure: Error & Equatable>(_ result: Result<Success, Error>?, _ error: Failure,
                                                         _ message: @autoclosure () -> String = "",
                                                         file: StaticString = #file, line: UInt = #line)
{
  if case .failure(let e)? = result
  {
    XCTAssertEqual(e, error, message(), file: file, line: line)
  }
  else
  {
    XCTAssertEqual(nil, error, message(), file: file, line: line)
  }
}
