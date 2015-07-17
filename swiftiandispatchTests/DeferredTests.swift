//
//  swiftiandispatchTests.swift
//  swiftiandispatchTests
//
//  Created by Guillaume Lessard on 2015-07-10.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest

import swiftiandispatch

class DeferredTests: XCTestCase
{
  func testExample()
  {
    syncprint("Starting")

    let result1 = async {
      _ -> Double in
      defer { syncprint("Computing result1") }
      return 10.5
    }.delay(ms: 50)

    let result2 = result1.map {
      (d: Double) -> Int in
      syncprint("Computing result2")
      return Int(floor(2*d))
    }.delay(ms: 50)

    let result3 = result1.map {
      (d: Double) -> String in
      syncprint("Computing result3")
      return (3*d).description
    }

    result3.notify { syncprint($0) }

    let result4 = result2.combine(result1.map { Int($0*4) })

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

  func testRace()
  {
    let count = 100
    let g = Determinable<Void>()
    let q = dispatch_get_global_queue(qos_class_self(), 0)

    let e = (0..<count).map { i in expectationWithDescription(i.description) }

    dispatch_async(q) {
      for i in 0..<count
      {
        dispatch_async(q) { g.notify { e[i].fulfill() } }
      }
    }

    dispatch_async(q) { try! g.determine() }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testApply1()
  {
    // a silly example curried function.
    func curriedSum(a: Int)(_ b: Int) -> Int
    {
      return a+b
    }

    let value1 = Int(arc4random())
    let value2 = Int(arc4random())
    let deferred = Deferred(value: value1).apply(Deferred(value: curriedSum(value2)))
    XCTAssert(deferred.value == value1+value2)
  }

  func testApply2()
  {
    let transform = Determinable<Int->Double>()
    let operand = Determinable<Int>()
    let result = operand.apply(transform)
    let expect = expectationWithDescription("Applying a deferred transform to a deferred operand")

    var v1 = 0
    var v2 = 0
    result.notify {
      result in
      print("\(v1), \(v2), \(result)")
      XCTAssert(result == Double(v1*v2))
      expect.fulfill()
    }

    let g = Determinable<Void>()

    g.delay(ms: 100).notify {
      v1 = Int(arc4random() & 0xffff + 10000)
      try! transform.determine { i in Double(v1*i) }
    }

    g.delay(ms: 200).notify {
      v2 = Int(arc4random() & 0xffff + 10000)
      try! operand.determine(v2)
    }

    XCTAssert(operand.peek() == nil)
    XCTAssert(operand.state == .Waiting)
    XCTAssert(transform.peek() == nil)
    XCTAssert(transform.state == .Waiting)

    try! g.determine()
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
    let deferred = Deferred(value: inputs[0])
    let deferreds = (1..<count).map { i in Deferred(value: inputs[i]) }

    let defarray = deferred.combine(deferreds)
    let values = defarray.value
    for (a,b) in zip(inputs, values)
    {
      XCTAssert(a == b)
    }

    let inputs2 = (0..<count).map { i in Deferred(value: arc4random()) }
    let defarray2 = combine(inputs2)
    let values2 = defarray2.value
    for (a,b) in zip(inputs2, values2)
    {
      XCTAssert(a.value == b)
    }

    let combined1 = combine([Deferred<Int>]())
    XCTAssert(combined1.value == [])

    let value = arc4random()
    let deferred2 = Deferred(value: value)
    let combined2 = deferred2.combine([])
    XCTAssert(combined2.value == [value])
  }

  func testFirstCompleted()
  {
    let count = 10
    let lucky = Int(arc4random_uniform(numericCast(count)))

    let deferreds = (0..<count).map {
      i -> Deferred<Int> in
      let e = expectationWithDescription(i.description)
      return Deferred {
        () -> Int in
        usleep(i == lucky ? 10_000 : 200_000)
        e.fulfill()
        return i
      }
    }

    let first = firstCompleted(deferreds)
    XCTAssert(first.value == lucky)
    waitForExpectationsWithTimeout(1.0, handler: nil)
  }
}