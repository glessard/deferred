//
//  DeferredTests.swift
//  async-deferred-tests
//
//  Created by Guillaume Lessard on 2015-07-10.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest

#if os(OSX)
  import async_deferred
#elseif os(iOS)
  import async_deferred_ios
#endif


class DeferredTests: XCTestCase
{
  func testExample()
  {
    syncprint("Starting")

    let result1 = async(QOS_CLASS_BACKGROUND) {
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

    result3.notify(QOS_CLASS_UTILITY) { syncprint($0) }

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
      _ -> Double in
      usleep(50000)
      return 1.0
    }
    print(d.value)
  }

  func testDelay()
  {
    let interval = 0.1
    let d1 = Deferred(value: NSDate())
    let d2 = d1.delay(seconds: interval).map { NSDate().timeIntervalSinceDate($0) }

    XCTAssert(d2.value >= interval)
    XCTAssert(d2.value < 2.0*interval)

    // a negative delay returns the same reference
    let d3 = d1.delay(ms: -1)
    XCTAssert(d3 === d1)

    let d4 = d1.delay(µs: -1).map { $0 }
    XCTAssert(d4.value == d3.value)

    // a longer calculation is not delayed (significantly)
    let d5 = Deferred {
      _ -> NSDate in
      NSThread.sleepForTimeInterval(interval)
      return NSDate()
    }
    let d6 = d5.delay(seconds: interval/10).map { NSDate().timeIntervalSinceDate($0) }
    let actualDelay = d6.value
    XCTAssert(actualDelay < interval/10)
  }

  func testValue()
  {
    let value = 1
    let d = Deferred(value: value)
    XCTAssert(d.value == value)
    XCTAssert(d.isDetermined)
  }

  func testPeek()
  {
    let value = 1
    let d1 = Deferred(value: value)
    XCTAssert(d1.peek()?.value == value)

    let d2 = Deferred(value: value).delay(µs: 10_000)
    XCTAssert(d2.isDetermined == false)
    XCTAssert(d2.peek() == nil)

    let expectation = expectationWithDescription("Waiting on Deferred")

    d2.notify { _ in
      XCTAssert(d2.peek()?.value == value)
      XCTAssert(d2.isDetermined)
      expectation.fulfill()
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testValueBlocks()
  {
    let waitns = 100_000_000

    let value = arc4random()

    let s = dispatch_semaphore_create(0)
    let busy = async { _ -> UInt32 in
      dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER)
      return value
    }

    let expectation = expectationWithDescription("Timing out on Deferred")
    let fulfillTime = dispatch_time(DISPATCH_TIME_NOW, numericCast(waitns))

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      let v = busy.value
      XCTAssert(v == value)

      let now = dispatch_time(DISPATCH_TIME_NOW, 0)
      if now < fulfillTime { XCTFail("delayed.value unblocked too soon") }
    }

    dispatch_after(fulfillTime, dispatch_get_global_queue(qos_class_self(), 0)) {
      expectation.fulfill()
    }

    waitForExpectationsWithTimeout(1.0) { _ in dispatch_semaphore_signal(s) }
  }

  func testValueUnblocks()
  {
    let waitns = 100_000_000

    let value = arc4random()

    let s = dispatch_semaphore_create(0)
    let busy = async { _ -> UInt32 in
      dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER)
      return value
    }

    let expectation = expectationWithDescription("Unblocking a Deferred")
    let fulfillTime = dispatch_time(DISPATCH_TIME_NOW, numericCast(waitns))

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      let v = busy.value
      XCTAssert(v == value)

      let now = dispatch_time(DISPATCH_TIME_NOW, 0)
      if now < fulfillTime { XCTFail("delayed.value unblocked too soon") }
      else                 { expectation.fulfill() }
    }

    dispatch_after(fulfillTime, dispatch_get_global_queue(qos_class_self(), 0)) {
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
    d2.notify(QOS_CLASS_BACKGROUND) {
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
    d3.notify {
      result in
      guard case let .Error(e) = result,
            let deferredErr = e as? DeferredError,
            case .Canceled = deferredErr
      else
      {
        XCTFail()
        return
      }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200_000_000), dispatch_get_global_queue(qos_class_self(), 0)) {
      e3.fulfill()
    }

    waitForExpectationsWithTimeout(1.0) { _ in d3.cancel() }
  }

  func testNotify4()
  {
    let d4 = Deferred(value: arc4random()).delay(ms: 50)
    let e4val = expectationWithDescription("Test onValue()")
    d4.onValue { _ in e4val.fulfill() }
    d4.onError { _ in XCTFail() }

    let d5 = Deferred<Void>(error: NSError(domain: "", code: 0, userInfo: nil)).delay(ms: 50)
    let e5err = expectationWithDescription("Test onError()")
    d5.onValue(QOS_CLASS_USER_INITIATED) { _ in XCTFail() }
    d5.onError(QOS_CLASS_UTILITY) { _ in e5err.fulfill() }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testMap()
  {
    let value = arc4random()
    let error = arc4random()
    let goodOperand = Deferred(value: value)
    let badOperand  = Deferred<Double>(error: TestError.Error(error))

    // good operand, good transform
    let d1 = goodOperand.map(QOS_CLASS_DEFAULT) { Int($0)*2 }
    XCTAssert(d1.value == Int(value)*2)
    XCTAssert(d1.error == nil)

    // good operand, transform throws
    let d2 = goodOperand.map { (i:UInt32) throws -> AnyObject in throw TestError.Error(i) }
    XCTAssert(d2.value == nil)
    XCTAssert(d2.error as? TestError == TestError.Error(value))

    // bad operand, transform short-circuited
    let d3 = badOperand.map { (d: Double) throws -> Int in XCTFail(); return 0 }
    XCTAssert(d3.value == nil)
    XCTAssert(d3.error as? TestError == TestError.Error(error))
  }

  func testFlatMap1()
  {
    let value = arc4random()
    let error = arc4random()
    let goodOperand = Deferred(value: value)
    let badOperand  = Deferred<Double>(error: TestError.Error(error))

    // good operand, good transform
    let d1 = goodOperand.flatMap(QOS_CLASS_DEFAULT) { Deferred(value: Int($0)*2) }
    XCTAssert(d1.value == Int(value)*2)
    XCTAssert(d1.error == nil)

    // good operand, transform throws
    let d2 = goodOperand.flatMap { Deferred<Double>(error: TestError.Error($0)) }
    XCTAssert(d2.value == nil)
    XCTAssert(d2.error as? TestError == TestError.Error(value))

    // bad operand, transform short-circuited
    let d3 = badOperand.flatMap { _ in Deferred<Void> { XCTFail() } }
    XCTAssert(d3.value == nil)
    XCTAssert(d3.error as? TestError == TestError.Error(error))
  }

  func testFlatMap2()
  {
    let value = arc4random()
    let error = arc4random()
    let goodOperand = Deferred(value: value)
    let badOperand  = Deferred<Double>(error: TestError.Error(error))

    // good operand, good transform
    let d1 = goodOperand.flatMap(QOS_CLASS_DEFAULT) { Result(value: Int($0)*2) }
    XCTAssert(d1.value == Int(value)*2)
    XCTAssert(d1.error == nil)

    // good operand, transform throws
    let d2 = goodOperand.flatMap { Result<Double>(error: TestError.Error($0)) }
    XCTAssert(d2.value == nil)
    XCTAssert(d2.error as? TestError == TestError.Error(value))

    // bad operand, transform short-circuited
    let d3 = badOperand.flatMap { _ in Result<Void> { XCTFail() } }
    XCTAssert(d3.value == nil)
    XCTAssert(d3.error as? TestError == TestError.Error(error))
  }

  func testApply()
  {
    let value = Int(arc4random() & 0xffff + 10000)
    let error = arc4random()

    let transform = Deferred { i throws -> Double in Double(value*i) }

    // good operand, good transform
    let o1 = Deferred(value: value)
    let r1 = o1.apply(transform)
    XCTAssert(r1.value == Double(value*value))
    XCTAssert(r1.error == nil)

    // bad operand, good transform
    let o2 = Deferred<Int> { throw TestError.Error(error) }
    let r2 = o2.apply(transform)
    XCTAssert(r2.value == nil)
    XCTAssert(r2.error as? TestError == TestError.Error(error))

    // good operand, transform throws
    let o3 = Deferred(value: error)
    let t3 = Deferred { (i:UInt32) throws -> AnyObject in throw TestError.Error(i) }
    let r3 = o3.apply(t3)
    XCTAssert(r3.value == nil)
    XCTAssert(r3.error as? TestError == TestError.Error(error))

    // good operand, bad transform
    let o4 = Deferred(value: value)
    let t4 = Deferred(error: TestError.Error(error)) as Deferred<(Int) throws -> dispatch_group_t>
    let r4 = o4.apply(t4)
    XCTAssert(r4.value == nil)
    XCTAssert(r4.error as? TestError == TestError.Error(error))

    // bad operand: transform not applied
    let o5 = Deferred<Int> { throw TestError.Error(error) }
    let t5 = Deferred { (i:Int) throws -> Float in XCTFail(); return Float(i) }
    let r5 = o5.apply(t5)
    XCTAssert(r5.value == nil)
    XCTAssert(r5.error as? TestError == TestError.Error(error))
  }

  func testCancel1()
  {
    let d1 = Deferred(qos: QOS_CLASS_UTILITY) {
      () -> UInt32 in
      usleep(10_000)
      return arc4random()
    }

    if d1.cancel()
    {
      XCTAssert(d1.value == nil)
    }
    else
    {
      XCTFail()
    }

    // Set before canceling -- cancellation failure
    let d4 = Deferred(value: arc4random())
    XCTAssert(d4.cancel("message") == false)
  }

  func testCancel2()
  {
    // Test specific paths for cancellation behaviour
    let tbd = TBD<Int>()

    let e1 = expectationWithDescription("map cancellation with good input")
    let d1 = tbd.map { $0 }
    d1.onError { e in e1.fulfill() }
    d1.cancel()

    let e2 = expectationWithDescription("map cancellation with error input")
    let d2 = d1.map { i -> Void in XCTFail() }
    d2.onError { e in e2.fulfill() }
    d2.cancel()

    let e3 = expectationWithDescription("flatMap cancellation with good input")
    let d3 = tbd.flatMap { Deferred(value: $0) }
    d3.onError { e in e3.fulfill() }
    d3.cancel()

    let e4 = expectationWithDescription("flatMap cancellation with error input")
    let d4 = d3.flatMap {
      i -> Deferred<Void> in
      XCTFail()
      return Deferred(value: ())
    }
    d4.onError { e in e4.fulfill() }
    d4.cancel()

    let e5 = expectationWithDescription("flatMap cancellation with Result")
    let d5 = tbd.flatMap { Result(value: $0) }
    d5.onError { e in e5.fulfill() }
    d5.cancel()

    let transform = Deferred(value: { (i: Int) throws -> Int in abs(i) } )

    let e6 = expectationWithDescription("apply cancellation with good inputs")
    let d6 = tbd.apply(transform)
    d6.onError { e in e6.fulfill() }
    d6.cancel()

    let e7 = expectationWithDescription("apply cancellation with error input")
    let d7 = d6.apply(transform)
    d7.onError { e in e7.fulfill() }
    d7.cancel()

    let e8 = expectationWithDescription("delay cancellation with good input")
    let d8 = tbd.delay(ms: 100)
    d8.onError { e in e8.fulfill() }
    d8.cancel()

    let e9 = expectationWithDescription("delay cancellation with error input")
    let d9 = d6.delay(ms: 100)
    d9.onError { e in e9.fulfill() }
    d9.cancel()

    do { try tbd.determine(1) }
    catch { XCTFail() }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testTimeout()
  {
    let value = arc4random()
    let d = Deferred(value: value)

    let d1 = d.timeout(ms: 50)
    XCTAssert(d1.value == value)

    let d2 = d.delay(ms: 5000).timeout(µs: 5000)
    let e2 = expectationWithDescription("Timeout test")
    d2.onValue { _ in XCTFail() }
    d2.onError { _ in e2.fulfill() }

    let d3 = d.delay(ms: 100).timeout(seconds: -1)
    let e3 = expectationWithDescription("Unreasonable timeout test")
    d3.onValue { _ in XCTFail() }
    d3.onError { _ in e3.fulfill() }

    let d4 = d.delay(ms: 50).timeout(ms: 100)
    let e4 = expectationWithDescription("Timeout test 4")
    d4.onValue { _ in e4.fulfill() }
    d4.onError { _ in XCTFail() }

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
    let deferred = Deferred(value: value1).apply(QOS_CLASS_USER_INITIATED, transform: Deferred(value: curriedSum(value2)))
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
    // let d4 = Deferred { v3 }                        // infers Deferred<()->String> rather than Deferred<String>
    // let d5 = Deferred { () -> String in v3 }        // infers Deferred<()->String> rather than Deferred<String>
    // let d6 = Deferred { _ in v3 }                   // infers Deferred<String> as expected
    // let d7 = Deferred { () throws -> String in v3 } // infers Deferred<String> as expected

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
