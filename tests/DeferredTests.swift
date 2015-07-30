//
//  DeferredTests.swift
//  async-deferred-tests
//
//  Created by Guillaume Lessard on 2015-07-10.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest

import async_deferred

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
    }.delay(ms: 500)

    let result3 = result1.map {
      (d: Double) -> String in
      syncprint("Computing result3")
      return (3*d).description
    }

    result3.notify { syncprint($0) }

    let result4 = result2.combine(result1.map { Int($0*4) })

    let result5 = result2.timeout(ms: 50)

    syncprint("Waiting")
    syncprint("Result 1: \(result1.result)")
    syncprint("Result 2: \(result2.result)")
    syncprint("Result 3: \(result3.result)")
    syncprint("Result 4: \(result4.result)")
    syncprint("Result 5: \(result5.result)")
    syncprint("Done")
    syncprintwait()
  }

  func testExample2()
  {
    let d = Deferred {
      () -> Double in
      usleep(50000)
      return 1.0
    }
    print(d.value)
  }

  func testDelay()
  {
    let interval = 0.01
    let d1 = Deferred(value: NSDate())
    let d2 = d1.delay(seconds: interval).map { NSDate().timeIntervalSinceDate($0) }

    // print(d2.value)
    XCTAssert(d2.value >= interval)
    XCTAssert(d2.value < 2*interval)

    // a negative delay passes back the same reference
    let d3 = d1.delay(ms: -1)
    XCTAssert(d3 === d1)

    let d4 = d1.delay(µs: -1).map { $0 }
    XCTAssert(d4.value == d3.value)

    // a longer calculation is not delayed (significantly)
    let d5 = Deferred {
      _ -> NSDate in
      NSThread.sleepForTimeInterval(10*interval)
      return NSDate()
    }
    let d6 = d5.delay(seconds: interval).map { NSDate().timeIntervalSinceDate($0) }
    let actualDelay = d6.value
    // print(actualDelay)
    XCTAssert(actualDelay < interval/10)
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
    XCTAssert(d1.peek()?.value == value)

    let d2 = Deferred(value: value).delay(µs: 100)
    XCTAssert(d2.peek() == nil)

    let expectation = expectationWithDescription("Waiting on Deferred")

    d2.notify { _ in
      if d2.peek()?.value == value
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

  func testValueBlocks()
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

  func testValueUnblocks()
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

  func testNotify1()
  {
    let value = arc4random()
    let e1 = expectationWithDescription("Pre-set Deferred")
    let d1 = Deferred(value: value)
    d1.notify {
      XCTAssert( $0.value == value )
      e1.fulfill()
    }
    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testNotify2()
  {
    let value = arc4random()
    let e2 = expectationWithDescription("Properly Deferred")
    let d2 = Deferred(value: value).delay(ms: 100)
    d2.notify {
      XCTAssert( $0.value == value )
      e2.fulfill()
    }
    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testNotify3()
  {
    let e3 = expectationWithDescription("Deferred forever")
    let d3 = Deferred { _ -> Int in
      let s3 = dispatch_semaphore_create(0)
      dispatch_semaphore_wait(s3, DISPATCH_TIME_FOREVER)
      return 42
    }
    d3.notify { _ in
      XCTFail()
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200_000_000), dispatch_get_global_queue(qos_class_self(), 0)) {
      e3.fulfill()
    }
    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testCancel()
  {
    let tbd1 = TBD<Void>()
    let reason = "unused"
    tbd1.cancel(reason)
    XCTAssert(tbd1.value == nil)
    switch tbd1.result
    {
    case .Value: XCTFail()
    case .Error(let error):
      if let e = error as? DeferredError, case .Canceled(let message) = e
      {
        XCTAssert(message == reason)
      }
      else { XCTFail() }
    }

    let tbd2 = Deferred(value: arc4random()).delay(ms: 5000)
    if tbd2.cancel()
    {
      XCTAssert(tbd2.value == nil)
    }
    else
    {
      XCTFail()
    }

    let e = expectationWithDescription("Cancel before setting")
    let tbd3 = TBD<UInt32>()
    Deferred(value: ()).delay(ms: 100).notify { _ in
      if tbd3.cancel() == false { XCTFail() }
    }
    Deferred(value: ()).delay(ms: 200).notify { _ in
      do {
        try tbd3.determine(arc4random())
        XCTFail()
      }
      catch DeferredError.AlreadyDetermined {
        e.fulfill()
      }
      catch {
        XCTFail()
      }
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testTimeout()
  {
    let value = arc4random()
    let d = Deferred(value: value)

    let d1 = d.timeout(ms: 50)
    XCTAssert(d1.value == value)

    let d2 = d.delay(ms: 5000).timeout(ms: 50)
    let e = expectationWithDescription("Timeout test")
    d2.onValue { _ in XCTFail() }
    d2.onError { _ in e.fulfill() }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testRace()
  {
    let count = 100
    let g = TBD<Void>()
    let q = dispatch_get_global_queue(qos_class_self(), 0)

    let e = (0..<count).map { i in expectationWithDescription(i.description) }

    dispatch_async(q) {
      for i in 0..<count
      {
        dispatch_async(q) { g.notify { _ in e[i].fulfill() } }
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
    let transform = TBD<(Int)throws->Double>()
    let operand = TBD<Int>()
    let result = operand.apply(transform)
    let expect = expectationWithDescription("Applying a deferred transform to a deferred operand")

    var v1 = 0
    var v2 = 0
    result.notify {
      result in
      print("\(v1), \(v2), \(result)")
      XCTAssert(result.value == Double(v1*v2))
      expect.fulfill()
    }

    let g = TBD<Void>()

    g.delay(ms: 100).notify { _ in
      v1 = Int(arc4random() & 0xffff + 10000)
      try! transform.determine { i in Double(v1*i) }
    }

    g.delay(ms: 200).notify { _ in
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

    let d1 = Deferred(value: v1).delay(ms: 100)
    let d2 = Deferred(value: v2).delay(ms: 200)

    let c = d1.combine(d2).value
    XCTAssert(c?.0 == v1)
    XCTAssert(c?.1 == v2)
  }

  func testCombine3()
  {
    let v1 = Int(arc4random())
    let v2 = UInt64(arc4random())
    let v3 = arc4random().description

    let d1 = Deferred(value: v1).delay(ms: 100)
    let d2 = Deferred(value: v2).delay(ms: 200)
    let d3 = Deferred(value: v3)
    // let d3 = Deferred { v3 }                        // infers Deferred<()->String> rather than Deferred<String>
    // let d3 = Deferred { () -> String in v3 }        // infers Deferred<()->String> rather than Deferred<String>
    // let d3 = Deferred { _ in v3 }                   // infers Deferred<String> as expected
    // let d3 = Deferred { () throws -> String in v3 } // infers Deferred<String> as expected

    let c = d1.combine(d2,d3).value
    XCTAssert(c?.0 == v1)
    XCTAssert(c?.1 == v2)
    XCTAssert(c?.2 == v3)
  }

  func testCombine4()
  {
    let v1 = Int(arc4random())
    let v2 = UInt64(arc4random())
    let v3 = arc4random().description
    let v4 = sin(Double(v2))

    let d1 = Deferred(value: v1).delay(ms: 100)
    let d2 = Deferred(value: v2).delay(ms: 200)
    let d3 = Deferred(value: v3)
    let d4 = Deferred(value: v4).delay(µs: 999)

    let c = d1.combine(d2,d3,d4).value
    XCTAssert(c?.0 == v1)
    XCTAssert(c?.1 == v2)
    XCTAssert(c?.2 == v3)
    XCTAssert(c?.3 == v4)
  }

  func testCombineArray()
  {
    let count = 10

    let inputs = (0..<count).map { i in Deferred(value: arc4random()) }
    let combined = combine(inputs)
    if let values = combined.value
    {
      XCTAssert(values.count == count)
      for (a,b) in zip(inputs, values)
      {
        XCTAssert(a.value == b)
      }
    }
    else { XCTFail() }

    let combined1 = combine([Deferred<Int>]())
    XCTAssert(combined1.value?.count == 0)

    let inputs2 = { _ -> [Deferred<UInt32>] in
      var inputs = inputs
      inputs.insert(Deferred(error: DeferredError.Canceled("")), atIndex: Int(arc4random_uniform(numericCast(inputs.count))))
      return inputs
    }()
    let combined2 = combine(inputs2)
    XCTAssert(combined2.value == nil)
    XCTAssert(combined2.error != nil)
  }
}
