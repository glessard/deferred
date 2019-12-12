//
//  ResolverTests.swift
//  deferred-tests
//
//  Created by Guillaume Lessard on 2015-07-28.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation
import Dispatch

import deferred

class ResolverTests: XCTestCase
{
  func testResolve1()
  {
    var (i, d) = Deferred<Int, TestError>.CreatePair()
    i.beginExecution()
    let value = nzRandom()
    XCTAssert(i.resolve(value: value))
    XCTAssert(d.isResolved)
    XCTAssert(d.value == value)
    XCTAssert(d.error == nil)

    (i, d) = Deferred<Int, TestError>.CreatePair()
    i.beginExecution()
    XCTAssertEqual(i.resolve(error: TestError(value)), true)
    XCTAssertEqual(d.state, .resolved)
    XCTAssertEqual(d.value, nil)
    XCTAssertEqual(d.error, TestError(value))
  }

  func testResolve2()
  {
    let (i, d) = Deferred<Int, Never>.CreatePair()
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

  func testResolverWithoutDeferred()
  {
    let r = Deferred<Int, Never>.CreatePair().resolver

    XCTAssertEqual(r.needsResolution, false)
    XCTAssertEqual(r.resolve(value: .max), false)
    XCTAssertEqual(r.cancel(), false)
    XCTAssertEqual(r.qos, .unspecified)
  }

  func testCancel() throws
  {
    var (i, d) = Deferred<Int, Error>.CreatePair()
    let reason = "unused"
    i.cancel(reason)
    XCTAssert(d.value == nil)
    do {
      _ = try d.get()
      XCTFail()
    }
    catch Cancellation.canceled(let message) {
      XCTAssert(message == reason)
    }

    let e = expectation(description: "Cancel before setting")
    (i, d) = Deferred<Int, Error>.CreatePair()
    i.cancel()
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.1) {
      i.resolve(value: nzRandom()) ?  XCTFail() : e.fulfill()
    }

    waitForExpectations(timeout: 1.0)
    XCTAssertNil(d.value)
  }

  func testNotify()
  {
    let (r, d) = Deferred<Int, Never>.CreatePair()

    let e = expectation(description: #function)
    r.notify { e.fulfill() }

    r.resolve(value: Int.random(in: 1..<10))
    waitForExpectations(timeout: 0.1)
    XCTAssertNotNil(d.value)
  }

  func testNeverResolved()
  { // a Deferred that cannot be resolved normally.
    let first = Deferred<Int, Cancellation>() { _ in }

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
}

class ParallelTests: XCTestCase
{
  func testParallel1()
  {
    let count = 10

    // Verify that the right number of Deferreds get created

    let e = (0..<count).map { expectation(description: "\($0)") }
    let deferreds = Deferred.inParallel(count: count, qos: .utility) { i in e[i].fulfill() }
    XCTAssertEqual(deferreds.count, count)
    waitForExpectations(timeout: 1.0)
  }

  func testParallel2() throws
  {
    let count = 10

    // Verify that all created Deferreds do the right job

    let arrays = Deferred.inParallel(count: count) {
      index throws in
      (0..<count).map { i in index*count+i }
    }

    let combined = combine(arrays)
    let resolved = combined.map { $0.flatMap({$0}) }

    let value = try resolved.get()
    XCTAssert(value.count == count*count)
    value.enumerated().forEach { XCTAssertEqual($0, $1) }
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
    let deferreds = Deferred.inParallel(count: 10, queue: .global(qos: .utility)) {
      i throws -> Int in
      guard (i%2 == 0) else { throw Invalidation.invalid("") }
      return i
    }

    let c = deferreds.compactMap({ $0.error }).count
    XCTAssert(c == 5)
  }
}
