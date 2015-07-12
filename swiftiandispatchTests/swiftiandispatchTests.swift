//
//  swiftiandispatchTests.swift
//  swiftiandispatchTests
//
//  Created by Guillaume Lessard on 2015-07-10.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest

import swiftiandispatch

let sleeptime = 50_000

class swiftiandispatchTests: XCTestCase
{
  func testExample()
  {
    syncprint("Starting")

    let result1 = async {
      _ -> Double in
      defer { syncprint("Computing result1") }
      return 10.1
    }.delay(sleeptime)

    let result2 = result1.map {
      (d: Double) -> Int in
      syncprint("Computing result2")
      usleep(numericCast(sleeptime))
      return Int(floor(2*d))
    }

    let result3 = result1.map {
      (d: Double) -> String in
      syncprint("Computing result3")
      return (3*d).description
    }

    result3.notify { syncprint($0) }

    let result4 = result2.combine(result2)

    syncprint("Waiting")
    syncprint("Result 1: \(result1.value)")
    syncprint("Result 2: \(result2.value)")
    syncprint("Result 3: \(result3.value)")
    syncprint("Result 4: \(result4.value)")
    syncprint("Done")
    syncprintwait()
  }

  func testValue()
  {
    let value = 1
    let d = Deferred(value: value)
    XCTAssert(d.value == value)
  }

  func testPeek()
  {
    let value = 1
    let d1 = Deferred(value: value)
    XCTAssert(d1.peek() == value)

    let d2 = delay(µs: 100).map { value }
    XCTAssert(d2.peek() == nil)

    let expectation = expectationWithDescription("Waiting on Deferred")

    d2.notify { _ in
      if d2.peek() == value
      {
        expectation.fulfill()
      }
      else
      {
        XCTFail()
      }
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testBlockingOfValue()
  {
    let start = dispatch_time(DISPATCH_TIME_NOW, 0)
    let waitns = 100_000_000 as dispatch_time_t

    let value = arc4random()

    let s = dispatch_semaphore_create(0)
    let busy = async { _ -> UInt32 in
      dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER)
      return value
    }

    let expectation = expectationWithDescription("Timing out on Deferred")

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      let v = busy.value
      XCTAssert(v == value)
      let now = dispatch_time(DISPATCH_TIME_NOW, 0)
      if now-start < waitns { XCTFail("delayed.value unblocked too soon") }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, numericCast(waitns)), dispatch_get_global_queue(qos_class_self(), 0)) {
      expectation.fulfill()
    }

    waitForExpectationsWithTimeout(1.0) { _ in dispatch_semaphore_signal(s) }
  }

  func testUnblockingOfValue()
  {
    let start = dispatch_time(DISPATCH_TIME_NOW, 0)
    let waitns = 100_000_000 as dispatch_time_t

    let value = arc4random()

    let s = dispatch_semaphore_create(0)
    let busy = async { _ -> UInt32 in
      dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER)
      return value
    }

    let expectation = expectationWithDescription("Unblocking a Deferred")

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      let v = busy.value
      XCTAssert(v == value)

      let now = dispatch_time(DISPATCH_TIME_NOW, 0)
      if now-start < waitns { XCTFail("delayed.value unblocked too soon") }
      else                  { expectation.fulfill() }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, numericCast(waitns)), dispatch_get_global_queue(qos_class_self(), 0)) {
      dispatch_semaphore_signal(s)
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testNotify()
  {
    let value = arc4random()
    let e1 = expectationWithDescription("Pre-set Deferred")
    let d1 = Deferred(value: value)
    d1.notify {
      XCTAssert( $0 == value )
      e1.fulfill()
    }

    let e2 = expectationWithDescription("Properly Deferred")
    let d2 = delay(ms: 100).map { value }
    d2.notify {
      XCTAssert( $0 == value )
      e2.fulfill()
    }

    let e3 = expectationWithDescription("Deferred forever")
    let d3 = Deferred { _ -> Int in
      let s3 = dispatch_semaphore_create(0)
      dispatch_semaphore_wait(s3, DISPATCH_TIME_FOREVER)
      return 42
    }
    d3.notify { _ in XCTFail() }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200_000_000), dispatch_get_global_queue(qos_class_self(), 0)) {
      e3.fulfill()
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testCombine2()
  {
    let v1 = Int(arc4random())
    let v2 = UInt64(arc4random())

    let d1 = delay(ms: 100).map { v1 }
    let d2 = delay(ms: 200).map { v2 }

    let c = d1.combine(d2).value
    XCTAssert(c.0 == v1)
    XCTAssert(c.1 == v2)
  }

  func testCombine3()
  {
    let v1 = Int(arc4random())
    let v2 = UInt64(arc4random())
    let v3 = arc4random().description

    let d1 = delay(ms: 100).map { v1 }
    let d2 = delay(ms: 200).map { v2 }
    let d3 = Deferred { v3 }

    let c = d1.combine(d2,d3).value
    XCTAssert(c.0 == v1)
    XCTAssert(c.1 == v2)
    XCTAssert(c.2 == v3)
  }

  func testCombineArray()
  {
    let count = 10

    let inputs = (0..<count).map { _ in arc4random() }
    let deferreds = (1..<count).map { i in Deferred(value: inputs[i]) }

    let def = Deferred(value: inputs[0])

    let defarray = def.combine(deferreds)
    let values = defarray.value
    for (a,b) in zip(inputs, values)
    {
      XCTAssert(a == b)
    }
  }

  func testFirstCompleted()
  {
    let count = 10
    let lucky = Int(arc4random_uniform(numericCast(count)))

    let deferreds = (1..<count).map {
      i -> Deferred<Int> in
      return Deferred {
        _ -> Int in
        usleep(i == lucky ? 10_000 : 1_000_000)
        return i
      }
    }

    let first = firstCompleted(deferreds)
    XCTAssert(first.value == lucky)
  }
}
