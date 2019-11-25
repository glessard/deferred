//
//  DeferredTimeoutTests.swift
//  deferred
//
//  Created by Guillaume Lessard
//  Copyright © 2019 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation
import Dispatch

import deferred

class DeferredTimeoutTests: XCTestCase
{
  func testTimeout1()
  {
    let t1 = Deferred<Int, TestError>(task: { _ in }).timeout(.seconds(-1), reason: "a")
    XCTAssertEqual(t1.error, Cancellation.timedOut("a"))

    let t2 = Deferred<Int, NSError>(value: 0).timeout(after: .distantFuture)
    XCTAssertNil(t2.error)

    let t3 = Deferred<Int, Error>(task: { _ in }).timeout(seconds: 0.01, reason: "b")
    XCTAssertEqual(t3.error, Cancellation.timedOut("b"))
  }

  func testTimeout2()
  {
    let t1 = Deferred<Int, Cancellation>(task: { _ in }).timeout(.seconds(-1), reason: "a")
    XCTAssertEqual(t1.error, .timedOut("a"))

    let t2 = Deferred<Int, Cancellation>(value: 0).timeout(after: .distantFuture)
    XCTAssertNil(t2.error)

    let t3 = Deferred<Int, Cancellation>(task: { _ in }).timeout(seconds: 0.01, reason: "b")
    XCTAssertEqual(t3.error, .timedOut("b"))
  }

  func testTimeout3()
  {
    let t1 = Deferred<Int, Never>(task: { _ in }).timeout(.seconds(-1), reason: "a")
    XCTAssertEqual(t1.error, .timedOut("a"))

    let t2 = Deferred<Int, Never>(value: 0).timeout(after: .distantFuture)
    XCTAssertNil(t2.error)

    let t3 = Deferred<Int, Never>(task: { _ in }).timeout(seconds: 0.01, reason: "b")
    XCTAssertEqual(t3.error, .timedOut("b"))
  }
}
