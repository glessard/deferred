//
//  DeferredDelayTests.swift
//  deferredTests
//
//  Created by Guillaume Lessard
//  Copyright © 2017-2019 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation
import Dispatch

import deferred

class DelayTests: XCTestCase
{
  func testDelayValue()
  {
    let t1 = 0.05
    let d1 = Deferred<Date, Never>(value: Date()).delay(seconds: t1).map { Date().timeIntervalSince($0) }
    XCTAssertGreaterThan(d1.value!, t1)
  }

  func testDelayError()
  {
    let d1 = Deferred<Date, Cancellation>(value: Date()).delay(until: .distantFuture)
    let d2 = d1.delay(seconds: 0.05)
    d1.cancel()
    XCTAssertEqual(d2.value, nil)
  }

  func testCancelDelay()
  {
    let d0 = Deferred<Date, Cancellation>(value: Date())
    let d1 = d0.delay(until: .now() + 0.1)
    let e1 = expectation(description: #function)
    XCTAssertEqual(d1.state, .waiting)
    d1.onError { _ in e1.fulfill() }
    XCTAssertEqual(d1.state, .executing)
    d1.cancel()
    XCTAssertEqual(d1.error, .canceled(""))

    waitForExpectations(timeout: 0.1)
  }

  func testSourceSlowerThanDelay()
  {
    let d1 = Deferred<Int, Never>(value: nzRandom()).delay(.milliseconds(100))
    let d2 = d1.delay(until: .now() + .microseconds(100))
    XCTAssertEqual(d1.value, d2.value)
    XCTAssertNotNil(d2.value)
  }

  func testDelayToThePast()
  {
    let d1 = Deferred<Int, Never>(value: nzRandom())
    let d2 = d1.delay(until: .now() - 1.0)
    XCTAssertEqual(d1.value, d2.value)
    XCTAssertEqual(ObjectIdentifier(d1), ObjectIdentifier(d2))
  }

  func testDistantFutureDelay()
  {
    let d1 = Deferred<Date, Never>(value: Date())
    let d2 = d1.delay(until: .distantFuture)

    XCTAssertEqual(d1.state, .resolved)
    XCTAssertEqual(d2.state, .waiting)

    d2.onValue { _ in fatalError(#function) }
    XCTAssertEqual(d2.state, .executing)
  }
}
