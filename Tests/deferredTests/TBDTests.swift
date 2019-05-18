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
  func testResolve1()
  {
    var (i, d) = TBD<Int>.CreatePair()
    i.beginExecution()
    let value = nzRandom()
    XCTAssert(i.resolve(value: value))
    XCTAssert(d.isResolved)
    XCTAssert(d.value == value)
    XCTAssert(d.error == nil)

    (i, d) = TBD<Int>.CreatePair()
    i.beginExecution()
    XCTAssert(i.resolve(error: TestError(value)))
    XCTAssert(d.isResolved)
    XCTAssert(d.value == nil)
    XCTAssert(d.error == TestError(value))
  }

  func testResolve2()
  {
    let (i, d) = TBD<Int>.CreatePair()
    i.beginExecution()
    var value = nzRandom()
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.01) {
      value = nzRandom()
      XCTAssert(i.resolve(value: value))
    }

    XCTAssert(d.isResolved == false)

    // Block until tbd becomes resolved
    XCTAssert(d.value == value)
    XCTAssert(d.error == nil)

    // Try and fail to resolve tbd a second time.
    XCTAssert(i.resolve(value: value) == false)
  }

  func testResolverWithoutTBD()
  {
    let r = TBD<Int>.CreatePair().resolver

    XCTAssertEqual(r.needsResolution, false)
    XCTAssertEqual(r.resolve(value: .max), false)
    XCTAssertEqual(r.cancel(), false)
    XCTAssertEqual(r.qos, .unspecified)
  }

  func testCancel() throws
  {
    var (i, d) = TBD<Int>.CreatePair()
    let reason = "unused"
    i.cancel(reason)
    XCTAssert(d.value == nil)
    do {
      _ = try d.get()
      XCTFail()
    }
    catch DeferredError.canceled(let message) { XCTAssert(message == reason) }

    let e = expectation(description: "Cancel before setting")
    (i, d) = TBD<Int>.CreatePair()
    i.cancel()
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.1) {
      i.resolve(value: nzRandom()) ?  XCTFail() : e.fulfill()
    }

    waitForExpectations(timeout: 1.0)
    XCTAssertNil(d.value)
  }

  func testOnResolution1()
  {
    let value = nzRandom()
    let e1 = expectation(description: "TBD notification after resolution")
    let (i, d1) = TBD<Int>.CreatePair()
    i.resolve(value: value)

    d1.onResult {
      XCTAssert( $0.value == value )
      e1.fulfill()
    }
    waitForExpectations(timeout: 1.0)
  }

  func testOnResolution2()
  {
    let e2 = expectation(description: "TBD notification after delay")
    let (i, d2) = TBD<Int>.CreatePair()

    var value = nzRandom()
    d2.onResult {
      XCTAssert( $0.value == value )
      e2.fulfill()
    }

    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 10e-6) {
      value = nzRandom()
      XCTAssert(i.resolve(value: value))
    }

    waitForExpectations(timeout: 1.0)
  }

  func testOnResolution3()
  {
    let e3 = expectation(description: "TBD never resolved")
    let d3 = TBD<Int>() { _ in }
    d3.onResult {
      result in
      XCTAssert(result.error as? DeferredError == DeferredError.canceled(""))
    }
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.2) {
      // This will trigger the completion handler at the `waitForExpectations` call below.
      e3.fulfill()
    }
    waitForExpectations(timeout: 1.0, handler: { _ in d3.cancel() })
  }

  func testOnResolution4()
  {
    let e = expectation(description: "TBD resolution chain")
    let (t1, d1) = TBD<Int>.CreatePair()
    let (t2, d2) = TBD<Int>.CreatePair()
    let r = nzRandom()

    d1.onResult(task: { o in t2.resolve(o) })
    d2.onResult {
      o in
      XCTAssert(o.isValue)
      if o.value == r { e.fulfill() }
    }

    t1.resolve(value: r)

    waitForExpectations(timeout: 1.0)
  }

  func testNeverResolved()
  {
    // a Deferred that will never become resolved.
    let first = TBD<Int>() { _ in }

    let other = first.map { XCTFail(String($0)) }
    let third = other.map { XCTFail(String(describing: $0)) }

    XCTAssert(first.isResolved == false)
    XCTAssert(other.isResolved == false)
    XCTAssert(third.isResolved == false)

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

  func testParallel2() throws
  {
    let count = 10

    // Verify that all created Deferreds do the right job

    let arrays = Deferred.inParallel(count: count) {
      index in
      (0..<count).map { i in index*count+i }
    }

    let combined = combine(arrays)
    let resolved = combined.map { $0.flatMap({$0}) }

    let value = try resolved.get()
    XCTAssert(value.count == count*count)
    value.enumerated().forEach { XCTAssert($0 == $1, "\($0) should equal \($1)") }
  }

  func testParallel3() throws
  {
    // Verify that "accidentally" passing a serial queue to inParallel doesn't cause a deadlock

    let q = DispatchQueue(label: "test1", qos: .utility)

    let count = 20
    let d = Deferred.inParallel(count: count, queue: q) { $0 }
    let c = combine(d)
    let value = try c.get()
    XCTAssert(value.count == count)
  }

  func testParallel4()
  {
    let range = 0..<10
    let deferreds = range.deferredMap(task: {
      i throws -> Int in
      guard (i%2 == 0) else { throw DeferredError.invalid("") }
      return i
    })

    let c = deferreds.compactMap({ $0.error }).count
    XCTAssert(c == 5)
  }
}
