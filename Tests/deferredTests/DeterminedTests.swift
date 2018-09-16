//
//  DeterminedTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 6/5/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import XCTest

import deferred

class DeterminedTests: XCTestCase
{
  func testEquals()
  {
#if swift(>=4.1)
    let i1 = nzRandom()
    let i2 = nzRandom()
    let i3 = i1*i2

    let o3 = Determined(value: i1*i2)
    XCTAssert(o3 == Determined(value: i3))
    XCTAssert(o3 != Determined(value: i2))

    var o4 = o3
    o4 = Determined(error: TestError(i1))
    XCTAssert(o3 != o4)
    XCTAssert(o4 != Determined(error: TestError(i2)))
#endif
  }

  func testHashable()
  {
#if swift(>=4.2)
    let d1 = Determined<Int>(value: nzRandom())
    let d2 = Determined<Int>(error: TestError(nzRandom()))

    let set = Set([d1, d2])

    XCTAssert(set.contains(d1))
#endif
  }

  func testGetters() throws
  {
    let v1 = nzRandom()
    let v2 = nzRandom()

    let detValue = Determined<Int>(value: v1)
    let detError = Determined<Int>(error: TestError(v2))

    do {
      let v = try detValue.get()
      XCTAssert(v1 == v)

      let _ = try detError.get()
    }
    catch let error as TestError {
      XCTAssert(v2 == error.error)
    }

    XCTAssertNotNil(detValue.value)
    XCTAssertNotNil(detError.error)

    XCTAssertNil(detValue.error)
    XCTAssertNil(detError.value)

    XCTAssertTrue(detValue.isValue)
    XCTAssertTrue(detError.isError)

    XCTAssertFalse(detValue.isError)
    XCTAssertFalse(detError.isValue)
  }

  func testCustomStringConvertible() throws
  {
    let value = Determined(value: 1)
    let error = value.isError ? value : Determined(error: TestError(1))

    let v = String(describing: value)
    let e = String(describing: error)

    XCTAssert(v != e)
    // print(v, "\n", e, separator: "")
  }
}
