//
//  TestError.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-09-24.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

enum TestError: Error, Equatable
{
  case value(Int)

  var error: Int {
    switch self { case .value(let v): return v }
  }

  init(_ e: Int = 0) { self = .value(e) }
}

func == <E: Error & Equatable>(lhs: Error?, rhs: E) -> Bool
{
  if let e = lhs as? E
  {
    return e == rhs
  }
  return false
}

func == <E: Error & Equatable>(lhs: E, rhs: Error?) -> Bool
{
  return rhs == lhs
}


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
