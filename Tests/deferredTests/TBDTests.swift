//
//  TBDTests.swift
//  async-deferred-tests
//
//  Created by Guillaume Lessard on 2015-07-28.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation
import Dispatch

import deferred


class TBDTests: XCTestCase
{
  static var allTests = [
    ("testDetermine1", testDetermine1),
    ("testDetermine2", testDetermine2),
    ("testCancel", testCancel),
    ("testNotify1", testNotify1),
    ("testNotify2", testNotify2),
    ("testNotify3", testNotify3),
    ("testNeverDetermined", testNeverDetermined),
    ("testParallel1", testParallel1),
    ("testParallel2", testParallel2),
    ("testParallel3", testParallel3),
    ("testState", testState),
  ]

  func testDetermine1()
  {
    let tbd = TBD<Int>()
    tbd.beginExecution()
    let value = nzRandom()
    XCTAssert(tbd.determine(value))
    XCTAssert(tbd.isDetermined)
    XCTAssert(tbd.value == value)
    XCTAssert(tbd.error == nil)

    let tbe = TBD<Void>()
    tbe.beginExecution()
    XCTAssert(tbe.determine(TestError(value)))
    XCTAssert(tbe.isDetermined)
    XCTAssert(tbe.value == nil)
    XCTAssert(tbe.error as? TestError == TestError(value))
  }

  func testDetermine2()
  {
    let tbd = TBD<Int>()
    tbd.beginExecution()
    var value = nzRandom()
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.01) {
      value = nzRandom()
      XCTAssert(tbd.determine(value))
    }

    XCTAssert(tbd.isDetermined == false)

    // Block until tbd becomes determined
    XCTAssert(tbd.value == value)
    XCTAssert(tbd.error == nil)

    // Try and fail to determine tbd a second time.
    XCTAssert(tbd.determine(value) == false)
  }

  func testCancel()
  {
    let tbd1 = TBD<Void>()
    let reason = "unused"
    tbd1.cancel(reason)
    XCTAssert(tbd1.value == nil)
    switch tbd1.result
    {
    case .value: XCTFail()
    case .error(let error):
      if let e = error as? DeferredError, case .canceled(let message) = e
      {
        XCTAssert(message == reason)
      }
      else { XCTFail() }
    }

    let e = expectation(description: "Cancel before setting")
    let tbd3 = TBD<Int>()
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.1) { XCTAssert(tbd3.cancel() == true) }
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.2) {
      if tbd3.determine(nzRandom())
      {
        XCTFail()
      }
      else
      {
        e.fulfill()
      }
    }

    waitForExpectations(timeout: 1.0)
  }

  func testState()
  {
    let d = TBD<Int>()
    XCTAssert(d.state == .waiting)

    d.beginExecution()
    XCTAssert(d.state == .executing)

    d.determine(1)
    XCTAssert(d.state == .determined)
  }

  func testNotify1()
  {
    let value = nzRandom()
    let e1 = expectation(description: "TBD notification after determination")
    let tbd = TBD<Int>()
    tbd.determine(value)

    tbd.notify {
      XCTAssert( $0 == Result.value(value) )
      e1.fulfill()
    }
    waitForExpectations(timeout: 1.0)
  }

  func testNotify2()
  {
    let e2 = expectation(description: "TBD notification after delay")
    let tbd = TBD<Int>()

    var value = nzRandom()
    tbd.notify {
      XCTAssert( $0 == Result.value(value) )
      e2.fulfill()
    }

    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 10e-6) {
      value = nzRandom()
      XCTAssert(tbd.determine(value))
    }

    waitForExpectations(timeout: 1.0)
  }

  func testNotify3()
  {
    let e3 = expectation(description: "TBD never determined")
    let d3 = TBD<Int>()
    d3.notify {
      result in
      do {
        _ = try result.getValue()
        XCTFail()
      }
      catch DeferredError.canceled {}
      catch { XCTFail() }
    }
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.2) {
      // This will trigger the `XCWaitCompletionHandler` in the `waitForExpectationsWithTimeout` call below.
      e3.fulfill()
    }
    waitForExpectations(timeout: 1.0) { _ in d3.cancel() }
  }

  func testNeverDetermined()
  {
    // a Deferred that will never become determined.
    let first = TBD<Int>()

    let other = first.map { XCTFail(String($0)) }
    let third = other.map { XCTFail(String(describing: $0)) }

    usleep(1000)

    XCTAssert(first.isDetermined == false)
    XCTAssert(other.isDetermined == false)
    XCTAssert(third.isDetermined == false)

    first.cancel()

    XCTAssertNil(first.value)
    XCTAssertNil(other.value)
    XCTAssertNil(third.value)
  }

  func testParallel1()
  {
    let count = 10

    // Verify that the right number of Deferreds get created

    let e = (0..<count).map { expectation(description: "\($0)") }
    _ = Deferred.inParallel(count: count, qos: .utility) { i in e[i].fulfill() }
    waitForExpectations(timeout: 1.0)
  }

  func testParallel2()
  {
    let count = 10

    // Verify that all created Deferreds do the right job

    let arrays = Deferred.inParallel(count: count) {
      index in
      (0..<count).map { i in index*count+i }
    }

    let combined = combine(arrays)
    let determined = combined.map { $0.flatMap({$0}) }

    switch determined.result
    {
    case .value(let value):
      XCTAssert(value.count == count*count)
      value.enumerated().forEach { XCTAssert($0 == $1, "\($0) should equal \($1)") }
    default: XCTFail()
    }
  }

  func testParallel3()
  {
    // Verify that "accidentally" passing a serial queue to inParallel doesn't cause a deadlock

    let q = DispatchQueue(label: "test1", qos: .utility)

    let count = 20
    let e = expectation(description: "e")
    let d = Deferred.inParallel(count: count, queue: q) { $0 }
    let c = combine(d)
    c.notify {
      r in
      switch r
      {
      case .value(let value):
        XCTAssert(value.count == count)
        e.fulfill()
      default: XCTFail()
      }
    }

    waitForExpectations(timeout: 1.0)
  }
}
