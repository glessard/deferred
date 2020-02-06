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
    let d = Deferred<Int, Never>(value: value)
    XCTAssertEqual(d.value, value)
    XCTAssertEqual(d.state, .resolved)
    XCTAssertEqual(d.error, nil)
  }

  func testError()
  {
    let value = nzRandom()
    let d = Deferred<Never, TestError>(error: TestError(value))
    XCTAssertEqual(d.value, nil)
    XCTAssertEqual(d.state, .resolved)
    XCTAssertEqual(d.error, TestError(value))
  }

  func testBeginExecution()
  {
    let q = DispatchQueue(label: #function)
    let e = expectation(description: #function)

    let r = nzRandom()
    var d: Deferred<Int, Never>! = nil
    q.async {
      d = Deferred<Int, Never>(queue: q) {
        resolver in
        resolver.resolve(value: r)
        e.fulfill()
      }
      XCTAssertEqual(d.state, .waiting)
      d.beginExecution()
      XCTAssertEqual(d.state, .executing)
    }

    waitForExpectations(timeout: 0.1)
    XCTAssertEqual(d.value, r)
    XCTAssertEqual(d.state, .resolved)
    d.beginExecution()
    XCTAssertEqual(d.state, .resolved)
  }

  func testPeek()
  {
    let value = nzRandom()
    let d1 = Deferred<Int, Error>(value: value)
    XCTAssertEqual(d1.peek(), value)

    let d2 = Deferred<Int, Cancellation> { _ in }
    XCTAssertEqual(d2.peek(), nil)
    XCTAssertEqual(d2.state, .waiting)

    d2.cancel(.timedOut(""))

    XCTAssertNotNil(d2.peek())
    XCTAssertEqual(d2.peek(), .timedOut(""))
    XCTAssertEqual(d2.state, .resolved)
  }

  func testValueBlocks()
  {
    let wait = 0.01

    let value = nzRandom()

    let s = DispatchSemaphore(value: 0)
    let busy = Deferred<Int, Never> {
      resolver in
      s.wait()
      resolver.resolve(value: value)
    }

    let e = expectation(description: "Timing out on Deferred")
    let fulfillTime = DispatchTime.now() + wait

    DispatchQueue.global().async {
      XCTAssertEqual(busy.state, .waiting)
      let v = busy.value
      XCTAssertEqual(busy.state, .resolved)
      XCTAssertEqual(v, value)

      if .now() < fulfillTime { XCTFail("delayed.value unblocked too soon") }
    }

    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: fulfillTime) {
      e.fulfill()
    }

    waitForExpectations(timeout: 0.1) { _ in s.signal() }
  }

  func testValueUnblocks()
  {
    let wait = 0.01

    let s = DispatchSemaphore(value: 0)
    let busy = Deferred<DispatchTimeoutResult, Never> {
      resolver in
      let timeoutResult = s.wait(timeout: .now() + wait)
      resolver.resolve(.success(timeoutResult))
    }

    let e = expectation(description: #function)
    let fulfillTime = DispatchTime.now() + wait

    DispatchQueue.global().async {
      XCTAssertEqual(busy.state, .waiting)
      let v = busy.value
      XCTAssertEqual(busy.state, .resolved)
      XCTAssertEqual(v, .timedOut)

      if .now() < fulfillTime { XCTFail("delayed.value unblocked too soon") }
      e.fulfill()
    }

    waitForExpectations(timeout: 0.1)
  }

  func testNotify()
  {
    let wait = 0.01

    let s = DispatchSemaphore(value: 0)
    let busy = Deferred<DispatchTimeoutResult, Never>(queue: .global(qos: .utility)) {
      resolver in
      let timeoutResult = s.wait(timeout: .now() + wait)
      resolver.resolve(value: timeoutResult)
    }

    let e1 = expectation(description: #function + "-1")
    busy.notify(queue: .global(qos: .userInteractive)) {
      result in
      e1.fulfill()
    }

    waitForExpectations(timeout: 0.1)

    let e2 = expectation(description: #function + "-2")
    busy.notify {
      result in
      e2.fulfill()
    }

    waitForExpectations(timeout: 0.1)
  }

  func testGet() throws
  {
    let d = Double(nzRandom())
    let e = TestError(1)
    let d1 = Deferred<Double, TestError>(value: d)
    let d2 = Deferred<Double, TestError>(error: e)
    var double = 0.0
    do {
      double = try d1.get()
      double = try d2.get()
      XCTFail()
    } catch let error as TestError {
      XCTAssertEqual(error, e)
    }

    XCTAssertEqual(double, d)
  }

  func testState()
  {
    let s = DispatchSemaphore(value: 0)
    let e = expectation(description: "state")

    let d = Deferred<DispatchTimeoutResult, Error>(task: { s.wait(timeout: .now() + 1.0) })
    d.notify(handler: { r in if case .success = r { e.fulfill() } })

    XCTAssertEqual(d.state, .executing)
    XCTAssertNotEqual(d.state, .resolved)

    s.signal()
    waitForExpectations(timeout: 1.0)

    XCTAssertEqual(d.state, .resolved)
  }

  func testNotifyWaiters() throws
  {
    let (t, d) = Deferred<Int, Never>.CreatePair()
    let s  = Deferred<Int, Never>(value: 0)
    let e1 = expectation(description: #function)
    d.notify(queue: .global(), handler: { _ in e1.fulfill()})
    t.retainSource(s)
    let e2 = expectation(description: #function)
    d.notify(queue: nil, handler: { _ in e2.fulfill() })
    let e3 = expectation(description: #function)
    d.notify(queue: DispatchQueue(label: #function), handler: { _ in e3.fulfill() })
    t.retainSource(s)

    let r = nzRandom()
    t.resolve(value: r)

    waitForExpectations(timeout: 0.1)
    XCTAssertEqual(d.value, r)
  }

  func testCancel()
  {
    // Cancel before calculation has run -- cancellation success
    let d1 = Deferred<Int, Error>(qos: .utility, task: { _ in })
    XCTAssertEqual(d1.cancel(), true)
    XCTAssertEqual(d1.value, nil)
    XCTAssertEqual(d1.error as? Cancellation, .canceled(""))

    // Set before canceling -- cancellation failure
    let d2 = Deferred<Int, Cancellation>(value: nzRandom())
    XCTAssertEqual(d2.cancel("message"), false)
    XCTAssertEqual(d2.error, nil)

    // Attempt to cancel a non-cancellable `Deferred`
    let d3 = Deferred { nzRandom() }
    XCTAssertEqual(d3.cancel(), false)
    XCTAssertEqual(d3.error, nil)
    XCTAssertNotNil(d3.value)
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
      XCTAssertEqual(String(describing: e), cancellationStrings[i])
    }

    let invalidations: [Invalidation] = [
      .invalid(""),
      .invalid(customMessage),
    ]

    let invalidationStrings = invalidations.map(String.init(describing:))
    // invalidationStrings.forEach({print($0)})

    for (i,e) in invalidations.enumerated()
    {
      XCTAssertEqual(String(describing: e), invalidationStrings[i])
    }
  }
}
