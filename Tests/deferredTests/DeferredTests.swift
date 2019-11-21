//
//  DeferredTests.swift
//  deferred-tests
//
//  Created by Guillaume Lessard on 2015-07-10.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation
import Dispatch

import deferred


class DeferredTests: XCTestCase
{
  func testValue()
  {
    let value = 1
    let d = Deferred<Int, Error>(value: value)
    XCTAssert(d.value == value)
    XCTAssert(d.isResolved)
  }

  func testPeek()
  {
    let value = 1
    let d1 = Deferred<Int, Error>(value: value)
    XCTAssert(d1.peek()?.value == value)

    let d2 = d1.delay(until: .distantFuture)
    XCTAssert(d2.peek() == nil)
    XCTAssert(d2.isResolved == false)

    _ = d2.cancel(.timedOut(""))

    XCTAssert(d2.peek() != nil)
    XCTAssert(d2.peek()?.error as? Cancellation == .timedOut(""))
    XCTAssert(d2.isResolved)
  }

  func testValueBlocks()
  {
    let wait = 0.1

    let value = nzRandom()

    let s = DispatchSemaphore(value: 0)
    let busy = Deferred<Int, Never> {
      s.wait()
      return .success(value)
    }

    let e = expectation(description: "Timing out on Deferred")
    let fulfillTime = DispatchTime.now() + wait

    DispatchQueue.global().async {
      let v = busy.value
      XCTAssert(v == value)

      let now = DispatchTime.now()
      if now.rawValue < fulfillTime.rawValue { XCTFail("delayed.value unblocked too soon") }
    }

    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: fulfillTime) {
      e.fulfill()
    }

    waitForExpectations(timeout: 1.0) { _ in s.signal() }
  }

  func testValueUnblocks()
  {
    let wait = 0.1

    let value = nzRandom()

    let s = DispatchSemaphore(value: 0)
    let busy = Deferred<Int, Never> {
      s.wait()
      return .success(value)
    }

    let e = expectation(description: "Unblocking a Deferred")
    let fulfillTime = DispatchTime.now() + wait

    DispatchQueue.global().async {
      let v = busy.value
      XCTAssert(v == value)

      let now = DispatchTime.now()
      if now.rawValue < fulfillTime.rawValue { XCTFail("delayed.value unblocked too soon") }
      else                 { e.fulfill() }
    }

    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: fulfillTime) {
      s.signal()
    }

    waitForExpectations(timeout: 1.0)
  }

  func testGet() throws
  {
    let d = 1.0
    let e = TestError(1)
    let d1 = Deferred<Double, TestError>(value: d)
    let d2 = Deferred<Double, TestError>(error: e)
    var double = 0.0
    do {
      double = try d1.get()
      double = try d2.get()
      XCTFail()
    } catch let error as TestError {
      XCTAssert(error == e)
    }

    XCTAssert(double == d)
  }

  func testState()
  {
    let s = DispatchSemaphore(value: 0)
    let e = expectation(description: "state")

    let d = Deferred<DispatchTimeoutResult, Error>(task: { s.wait(timeout: .now() + 1.0) })
    d.notify(handler: { r in if case .success = r { e.fulfill() } })

    XCTAssert(d.state == .executing)
    XCTAssertFalse(d.state.isResolved)

    s.signal()
    waitForExpectations(timeout: 1.0)

    XCTAssert(d.state == .succeeded)
    XCTAssert(d.state.isResolved)
  }

  func testNotifyWaiters() throws
  {
    let (t0, d0) = TBD<Int, Never>.CreatePair()
    let e1 = expectation(description: #function)
    d0.notify(queue: .global(), handler: { _ in e1.fulfill()})
    let e2 = expectation(description: #function)
    d0.notify(queue: nil, handler: { _ in e2.fulfill() })
    let e3 = expectation(description: #function)
    d0.notify(queue: DispatchQueue(label: #function), handler: { _ in e3.fulfill() })

    let r = nzRandom()
    t0.resolve(value: r)

    waitForExpectations(timeout: 0.1)
    XCTAssertEqual(r, try d0.get())
  }

  func testCancel()
  {
    let d1 = Deferred(qos: .utility, task: {
      () -> Int in
      usleep(100_000)
      return nzRandom()
    })

    XCTAssert(d1.cancel() == true)
    XCTAssert(d1.value == nil)

    // Set before canceling -- cancellation failure
    let d2 = Deferred<Int, Cancellation>(value: nzRandom())
    XCTAssert(d2.cancel("message") == false)

    if let e = d1.error as? Cancellation
    {
      XCTAssert(e.description != "")
      XCTAssert(e == .canceled(""))
    }
  }

  func testErrorTypes()
  {
    let customMessage = "Custom Message"

    let cancellations: [Cancellation] = [
      .canceled(""),
      .canceled(customMessage),
      .timedOut(""),
      .timedOut(customMessage),
      .notSelected
    ]

    let cancellationStrings = cancellations.map(String.init(describing: ))
    // cancellationStrings.forEach({print($0)})

    for (i,e) in cancellations.enumerated()
    {
      XCTAssert(String(describing: e) == cancellationStrings[i])
    }

    let invalidations: [Invalidation] = [
      .invalid(""),
      .invalid(customMessage),
    ]

    let invalidationStrings = invalidations.map(String.init(describing:))
    // invalidationStrings.forEach({print($0)})

    for (i,e) in invalidations.enumerated()
    {
      XCTAssert(String(describing: e) == invalidationStrings[i])
    }
  }
}
