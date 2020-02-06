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
    i.resolve(value: value)
    XCTAssertEqual(d.isResolved, true)
    XCTAssertEqual(d.value, value)
    XCTAssertEqual(d.error, nil)

    (i, d) = Deferred<Int, TestError>.CreatePair()
    i.beginExecution()
    i.resolve(error: TestError(value))
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
      i.resolve(value: value)
    }

    XCTAssertEqual(d.isResolved, false)

    // Block until tbd becomes resolved
    XCTAssertEqual(d.value, value)
    XCTAssertEqual(d.error, nil)

    // Try and fail to resolve tbd a second time.
    i.resolve(value: nzRandom())
  }

  func testResolverWithoutDeferred()
  {
    let r = Deferred<Int, Never>.CreatePair().resolver

    XCTAssertEqual(r.needsResolution, false)
    XCTAssertEqual(r.cancel(), false)
    XCTAssertEqual(r.qos, .unspecified)
  }

  func testCancel() throws
  {
    var (i, d) = Deferred<Int, Error>.CreatePair()
    let reason = "unused"
    i.cancel(reason)
    XCTAssertEqual(d.value, nil)
    do {
      _ = try d.get()
      XCTFail()
    }
    catch Cancellation.canceled(let message) {
      XCTAssertEqual(message, reason)
    }

    let e = expectation(description: "Cancel before setting")
    (i, d) = Deferred<Int, Error>.CreatePair()
    d.onError { _ in e.fulfill() }

    XCTAssertEqual(i.cancel(), true)
    i.resolve(value: nzRandom())

    waitForExpectations(timeout: 1.0)
    XCTAssertEqual(d.value, nil)
    XCTAssertEqual(d.result, Cancellation.canceled(""))
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

    let other = first.map { fatalError(String($0)) }
    XCTAssertEqual(first.isResolved, false)
    XCTAssertEqual(other.isResolved, false)

    first.cancel()
    XCTAssertEqual(first.value, nil)
    XCTAssertEqual(other.value, nil)
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
    XCTAssertEqual(value.count, count*count)
    value.enumerated().forEach { XCTAssertEqual($0, $1) }
  }

  func testParallel3() throws
  {
    // Verify that "accidentally" passing a serial queue to inParallel doesn't cause a deadlock

    let q = DispatchQueue(label: "test1", qos: .utility)

    let count = 20
    let d = Deferred.inParallel(count: count, queue: q) { $0 }
    let c = combine(d)
    let value = c.value
    XCTAssertEqual(value.count, count)
  }

  func testParallel4()
  {
    let deferreds = Deferred.inParallel(count: 10, queue: .global(qos: .utility)) {
      i throws -> Int in
      guard (i%2 == 0) else { throw Invalidation.invalid("") }
      return i
    }

    let c = deferreds.compactMap({ $0.error }).count
    XCTAssertEqual(c, 5)
  }
}
