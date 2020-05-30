//
//  DeferredDelayTests.swift
//  deferredTests
//
//  Created by Guillaume Lessard
//  Copyright © 2017-2020 Guillaume Lessard. All rights reserved.
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

  func testDelayedDemand()
  {
    let delay = 0.01
    let d1 = Deferred<Date, Never>(task: { $0.resolve(value: Date()) }).delayingDemand(seconds: delay)

    let t1 = Date()
    let t2 = d1.get()
    XCTAssertGreaterThanOrEqual(t2.timeIntervalSince(t1), delay)

    let t3 = Date()
    let d2 = Deferred<Date, Never>(task: { $0.resolve(value: Date()) }).delayingDemand(.seconds(-1))
    let d3 = d2.map { $0.timeIntervalSince(t3) }
    let t4 = d3.get()
    XCTAssertGreaterThanOrEqual(t4, 0)
    XCTAssertLessThanOrEqual(t4, delay) // this is not a robust assertion.
  }
}
