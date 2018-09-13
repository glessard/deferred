//
//  DeterminedTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 6/5/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import XCTest

@testable import deferred

class DeterminedTests: XCTestCase
{
  func testEquals1()
  {
#if swift (>=4.1)
    let t1 = TBD<Int>()
    let t2 = TBD<Int>()

    var v1 = 0
    var v2 = 0

    t1.onValue { v1 = $0 }
    t2.onValue { v2 = $0 }

    let e = expectation(description: "equality test")

    let t3 = t1.flatMap { i1 in t2.map { i2 in i1*i2 } }
    t3.notify {
      determined in
      let ref = Determined(value: v1*v2)
      XCTAssert(determined == ref)
#if swift(>=4.2)
      XCTAssert(determined.hashValue == ref.hashValue)
#endif
      e.fulfill()
    }

    t1.determine(nzRandom())
    t2.determine(nzRandom())

    waitForExpectations(timeout: 1.0)
#endif
  }

  func testEquals2()
  {
#if swift (>=4.1)
    let ev = nzRandom()

    let t1 = TBD<Int>()
    let t2 = t1.map { i -> Int in throw TestError(i) }

    let e1 = expectation(description: "equality test a")

    t1.notify {
      determined in
      let ref = Determined<Int>(error: TestError(ev))
      XCTAssert(determined != ref)
#if swift(>=4.2)
      XCTAssert(determined.hashValue != ref.hashValue)
#endif
      e1.fulfill()
    }

    let e2 = expectation(description: "equality test b")

    t2.notify {
      determined in
      let ref = Determined<Int>(error: TestError(ev))
      XCTAssert(determined == ref)
#if swift(>=4.2)
      XCTAssert(determined.hashValue == ref.hashValue)
#endif
      e2.fulfill()
    }

    t1.determine(ev)

    waitForExpectations(timeout: 1.0)
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
}
