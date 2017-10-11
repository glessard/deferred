//
//  DeferredTests.swift
//  async-deferred-tests
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
  static var allTests = [
    ("testExample", testExample),
    ("testExample2", testExample2),
    ("testExample3", testExample3),
    ("testDeferredError", testDeferredError),
    ("testDelay", testDelay),
    ("testValue", testValue),
    ("testPeek", testPeek),
    ("testValueBlocks", testValueBlocks),
    ("testValueUnblocks", testValueUnblocks),
    ("testState", testState),
    ("testGet", testGet),
    ("testOptional", testOptional),
    ("testNotify1", testNotify1),
    ("testNotify2", testNotify2),
    ("testNotify3", testNotify3),
    ("testNotify4", testNotify4),
    ("testMap", testMap),
    ("testRecover", testRecover),
    ("testRetry", testRetry),
    ("testFlatMap", testFlatMap),
    ("testFlatten", testFlatten),
    ("testApply", testApply),
    ("testApply1", testApply1),
    ("testApply2", testApply2),
    ("testApply3", testApply3),
    ("testQoS", testQoS),
    ("testCancel", testCancel),
    ("testCancelAndNotify", testCancelAndNotify),
    ("testCancelMap", testCancelMap),
    ("testCancelDelay", testCancelDelay),
    ("testCancelBind", testCancelBind),
    ("testCancelApply", testCancelApply),
    ("testTimeout", testTimeout),
    ("testValidate1", testValidate1),
    ("testValidate2", testValidate2),
  ].sorted(by: {$0.0 < $1.0})

  func testExample()
  {
    print("Starting")

    let result1 = Deferred(task: {
      () -> Double in
      defer { print("Computing result1") }
      return 10.5
    }).delay(.milliseconds(50))

    let result2 = result1.map {
      (d: Double) -> Int in
      print("Computing result2")
      return Int(floor(2*d))
    }.delay(.milliseconds(500))

    let result3 = result1.map {
      (d: Double) -> String in
      print("Computing result3")
      return (3*d).description
    }

    result3.notify { print("Result 3 is: \($0.value!)") }

    let result4 = combine(result1, result2)

    let result5 = result2.map(transform: Double.init).timeout(.milliseconds(50))

    print("Waiting")
    print("Result 1: \(result1.value!)")
    print("Result 2: \(result2.value!)")
    print("Result 3: \(result3.value!)")
    print("Result 4: \(result4.value!)")
    print("Result 5: \(result5.error!)")
    print("Done")

    XCTAssert(result1.error == nil)
    XCTAssert(result2.error == nil)
    XCTAssert(result3.error == nil)
    XCTAssert(result4.error == nil)
    XCTAssert(result5.value == nil)
  }

  func testExample2()
  {
    let d = Deferred {
      () -> Double in
      usleep(50000)
      return 1.0
    }
    d.value.map { print($0) }
  }

  func testExample3()
  {
    let transform = Deferred { i throws in Double(7*i) } // Deferred<Int throws -> Double>
    let operand = Deferred(value: 6)                     // Deferred<Int>
    let result = operand.apply(transform: transform)     // Deferred<Double>
    result.value.map { print($0) }                       // 42.0
  }

  func testDelay()
  {
    let d = Deferred(value: Date())

    let t1 = 0.05
    let d1 = d.delay(seconds: t1).map { Date().timeIntervalSince($0) }
    let e1 = expectation(description: "delay test 1")
    d1.onValue { if $0 >= t1 { e1.fulfill() } }

    let t2 = 0.01
    let s2 = d.delay(seconds: 0.05)
    let d2 = s2.delay(seconds: t2)
    let e2 = expectation(description: "long delay with source error")
    d2.onError { _ in e2.fulfill() }
    s2.cancel()

    // a negative delay returns the same reference
    let d3 = d.delay(.milliseconds(-1))
    XCTAssert(d3 === d)

    // a longer calculation is not (significantly) delayed
    let t4 = 0.1
    let d4 = Deferred(value: Date()).delay(seconds: t4).map(transform: { ($0, Date()) })
    let d5 = d4.delay(seconds: t4/10).map { (Date().timeIntervalSince($0), Date().timeIntervalSince($1)) }
    let e5 = expectation(description: "delay of long calculation")
    d5.onValue { if $0 > t4 && $1 < t4/10 { e5.fulfill() } }

    let t6 = TBD<Void>()
    let d6 = t6.delay(until: .distantFuture)
    let e6 = expectation(description: "cancel during delay, before source notifies")
    d6.cancel()
    t6.onError { _ in if d6.value == nil { e6.fulfill() } }
    t6.cancel()

    let d7 = d.delay(until: .distantFuture)
    let e7 = expectation(description: "indefinite delay (with cancellation)")
    d7.onError(task: { _ in e7.fulfill() })
    d7.cancel()

    waitForExpectations(timeout: 1.0, handler: nil)
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

    let d2 = d1.delay(until: .distantFuture)
    XCTAssert(d2.peek() == nil)
    XCTAssert(d2.isDetermined == false)

    _ = d2.cancel(.timedOut(""))

    XCTAssert(d2.peek() != nil)
    XCTAssert(d2.peek()?.error as? DeferredError == DeferredError.timedOut(""))
    XCTAssert(d2.isDetermined)
  }

  func testValueBlocks()
  {
    let wait = 0.1

    let value = nzRandom()

    let s = DispatchSemaphore(value: 0)
    let busy = Deferred<Int> {
      s.wait()
      return value
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

    waitForExpectations(timeout: 2.0) { _ in s.signal() }
  }

  func testValueUnblocks()
  {
    let wait = 0.1

    let value = nzRandom()

    let s = DispatchSemaphore(value: 0)
    let busy = Deferred<Int> {
      s.wait()
      return value
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

    waitForExpectations(timeout: 2.0)
  }

  func testGet() throws
  {
    let e = TestError(1)
    let d1 = Deferred(value: 1.0)
    let d2 = d1.map(transform: { _  throws -> Double in throw e})
    var double = Optional<Double>.none
    do {
      double = try d1.get()
      double = try d2.get()
      XCTFail()
    } catch let error as TestError {
      XCTAssert(error == e)
    }

    XCTAssert(double == 1.0)
  }

  func testState()
  {
    let s = DispatchSemaphore(value: 0)
    let e = expectation(description: "state")

    let d = Deferred(task: { s.wait(timeout: .now() + 1.0) })
    let m = d.map(transform: { r throws -> Void in if r == .success { throw DeferredError.invalid("") } })
    m.notify { _ in e.fulfill() }

    XCTAssert(d.state == .executing)
    XCTAssert(m.state == .waiting)
    XCTAssertFalse(d.state.isDetermined)
    XCTAssertFalse(m.state.isDetermined)

    s.signal()
    waitForExpectations(timeout: 0.1)

    XCTAssert(d.state == .succeeded)
    XCTAssert(d.state.isDetermined)
    XCTAssert(m.state == .errored)
    XCTAssert(m.state.isDetermined)
  }


  func testNotify1()
  {
    let value = nzRandom()
    let e1 = expectation(description: "Pre-set Deferred")
    let d1 = Deferred(value: value)
    d1.notify {
      XCTAssert( $0.value == value )
      e1.fulfill()
    }
    waitForExpectations(timeout: 1.0)
  }

  func testNotify2()
  {
    let value = nzRandom()
    let e2 = expectation(description: "Properly Deferred")
    let d1 = Deferred(qos: .background, value: value)
    let d2 = d1.delay(.milliseconds(100))
    d2.notify(queue: DispatchQueue(label: "Test", qos: .utility)) {
      XCTAssert( $0.value == value )
      e2.fulfill()
    }
    waitForExpectations(timeout: 1.0)
  }

  func testNotify3()
  {
    let e3 = expectation(description: "Deferred forever")
    let d3 = Deferred<Int> {
      let s3 = DispatchSemaphore(value: 0)
      s3.wait()
      return 42
    }
    d3.notify {
      determined in
      guard let e = determined.error,
            let deferredErr = e as? DeferredError,
            case .canceled = deferredErr
      else
      {
        XCTFail()
        return
      }
    }
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.2) {
      e3.fulfill()
    }

    waitForExpectations(timeout: 1.0) { _ in d3.cancel() }
  }

  func testNotify4()
  {
    let d4 = Deferred(value: nzRandom())
    let e4 = expectation(description: "Test onValue()")
    d4.onValue { _ in e4.fulfill() }
    d4.onError { _ in XCTFail() }

    let d5 = Deferred<Int>(error: NSError(domain: "", code: 0))
    let e5 = expectation(description: "Test onError()")
    d5.onValue { _ in XCTFail() }
    d5.onError { _ in e5.fulfill() }

    waitForExpectations(timeout: 1.0)
  }

  func testMap()
  {
    let value = nzRandom()
    let error = nzRandom()
    let goodOperand = Deferred(value: value)
    let badOperand  = Deferred<Double>(error: TestError(error))

    // good operand, good transform
    let d1 = goodOperand.map { Int($0)*2 }
    XCTAssert(d1.value == Int(value)*2)
    XCTAssert(d1.error == nil)

    // good operand, transform throws
    let d2 = goodOperand.map { throw TestError($0) }
    XCTAssert(d2.value == nil)
    XCTAssert(d2.error as? TestError == TestError(value))

    // bad operand, transform short-circuited
    let d3 = badOperand.map { _ in XCTFail() }
    XCTAssert(d3.value == nil)
    XCTAssert(d3.error as? TestError == TestError(error)) 
  }

  func testRecover()
  {
    let value = nzRandom()
    let error = nzRandom()
    let goodOperand = Deferred(value: value)
    let badOperand  = Deferred<Double>(error: TestError(error))

    // good operand, transform short-circuited
    let d1 = goodOperand.recover(qos: .default) { e in XCTFail(); return Deferred(error: TestError(error)) }
    XCTAssert(d1.value == value)
    XCTAssert(d1.error == nil)

    // bad operand, transform throws
    let d2 = badOperand.recover { error in Deferred { throw TestError(value) } }
    XCTAssert(d2.value == nil)
    XCTAssert(d2.error as? TestError == TestError(value))

    // bad operand, transform executes
    let d3 = badOperand.recover { error in Deferred(value: Double(value)) }
    XCTAssert(d3.value == Double(value))
    XCTAssert(d3.error == nil)

    // test early return from notification block
    let reason = "reason"
    let d4 = goodOperand.delay(.milliseconds(50))
    let r4 = d4.recover { e in Deferred(value: value) }
    XCTAssert(r4.cancel(reason))
    XCTAssert(r4.value == nil)
    if let e = r4.error as? DeferredError,
       case .canceled(let message) = e
    { XCTAssert(message == reason) }
    else { XCTFail() }
  }

  func testRetry()
  {
    let retries = 5

    var counter = 0
    let r1 = Deferred.RetryTask(retries) {
      () in
      counter += 1
      throw TestError(counter)
    }
    XCTAssert(r1.value == nil)
    XCTAssert(r1.error as? TestError == TestError(retries))
    XCTAssert(counter == retries)

    let r2 = Deferred.Retrying(0, task: { Deferred<Void>(task: {XCTFail()}) })
    if let e = r2.error as? DeferredError,
       case .invalid(let s) = e
    { _ = s } // print(s) }
    else { XCTFail() }

    counter = 0
    let r3 = Deferred.Retrying(retries) {
      () -> Deferred<Int> in
      counter += 1
      if counter < retries { return Deferred(error: TestError(counter)) }
      return Deferred(value: counter)
    }
    XCTAssert(r3.value == retries)

    counter = 0
    let r4 = Deferred.RetryTask(retries) {
      () throws -> Int in
      counter += 1
      guard counter < retries else { throw TestError(counter) }
      return counter
    }
    XCTAssert(r4.value == 1)
  }

  func testFlatMap()
  {
    let value = nzRandom()
    let error = nzRandom()
    let goodOperand = Deferred(value: value)
    let badOperand  = Deferred<Double>(error: TestError(error))

    // good operand, good transform
    let d1 = goodOperand.flatMap(qos: .utility, transform: { Deferred(value: Int($0)*2) })
    XCTAssert(d1.value == Int(value)*2)
    XCTAssert(d1.error == nil)

    // good operand, transform errors
    let d2 = goodOperand.flatMap { Deferred<Double>(error: TestError($0)) }
    XCTAssert(d2.value == nil)
    XCTAssert(d2.error as? TestError == TestError(value))

    // bad operand, transform short-circuited
    let d3 = badOperand.flatMap { _ in Deferred<Void> { XCTFail() } }
    XCTAssert(d3.value == nil)
    XCTAssert(d3.error as? TestError == TestError(error))
  }

  func testFlatten()
  {
    let value = nzRandom()
    let error = nzRandom()

    let goodOperand = Deferred(value: Deferred(value: value))
    let d1 = goodOperand.flatten()
    XCTAssert(d1.value == value)

    let badOperand1 = Deferred<Deferred<Int>>(error: TestError(error))
    let d2 = badOperand1.flatten()
    XCTAssert(d2.error as? TestError == TestError(error))

    let deferredValue = TBD<Deferred<Int>>()
    let d3 = deferredValue.flatten()
    let e3 = expectation(description: "flatten, part 3")
    d3.validate(predicate: { XCTAssertEqual($0, value) }).onValue(task: { _ in e3.fulfill() })
    deferredValue.determine(Deferred(value: value))

    let badOperand2 = TBD<Deferred<Int>>()
    let d4 = badOperand2.flatten()
    let e4 = expectation(description: "flatten, part 4")
    d4.recover(transform: { Deferred(error: $0) }).onError(task: { _ in e4.fulfill() })
    badOperand2.determine(TestError(error))

    let tbd = TBD<Int>()
    let fullyDeferred = Deferred(value: tbd.delay(seconds: 0.02)).delay(seconds: 0.01)
    let d5 = fullyDeferred.flatten()
    let e5 = expectation(description: "flatten, part 5")
    d5.validate(predicate: { XCTAssertEqual($0, value) }).onValue(task: { _ in e5.fulfill() })

    let semiDeferred = Deferred(value: tbd.delay(seconds: 0.01))
    let d6 = semiDeferred.flatten()
    let e6 = expectation(description: "flatten, part 6")
    d6.validate(predicate: { XCTAssertEqual($0, value) }).onValue(task: { _ in e6.fulfill() })

//    let willCompile = Deferred(value: d1).flatten()
//    let wontCompile = Deferred(value: 99).flatten()

    tbd.determine(value)

    waitForExpectations(timeout: 0.1)
  }

  func testApply()
  {
    // a simple curried function.
    let curriedSum: (Int) -> (Int) -> Int = { a in { b in (a+b) } }

    let value1 = Int(nzRandom())
    let value2 = Int(nzRandom())
    let v1 = Deferred(value: value1)
    let v2 = Deferred(value: curriedSum(value2))
    let deferred = v1.apply(transform: v2)
    XCTAssert(deferred.value == value1+value2)

    // tuples must be explicitly destructured
    let transform = Deferred(value: { (ft: (Float, Float)) in powf(ft.0, ft.1) })

    let v3 = Deferred(value: 3.0 as Float)
    let v4 = Deferred(value: 4.1 as Float)

    let args = combine(v3, v4)
    let result = args.apply(transform: transform)

    XCTAssert(result.value == powf(v3.value!, v4.value!))
  }

  func testApply1()
  {
    let transform = TBD<(Int) -> Double>()
    let operand = TBD<Int>()
    let result = operand.apply(qos: .background, transform: transform)
    let expect = expectation(description: "Applying a deferred transform to a deferred operand")

    var v1 = 0
    var v2 = 0
    result.notify {
      determined in
      XCTAssert(determined.value == (Double(v1*v2)))
      expect.fulfill()
    }

    let g = TBD<Int>()

    g.notify { _ in
      v1 = Int(nzRandom() & 0x7fff + 10000)
      transform.determine { i in Double(v1*i) }
    }

    g.notify { _ in
      v2 = Int(nzRandom() & 0x7fff + 10000)
      operand.determine(v2)
    }

    XCTAssertFalse(operand.isDetermined)
    XCTAssert(operand.state == .waiting)
    XCTAssertFalse(transform.isDetermined)
    XCTAssert(transform.state == .waiting)

    g.determine(0)
    waitForExpectations(timeout: 1.0)

    XCTAssert(transform.state == .succeeded)
  }

  func testApply2()
  {
    let value = nzRandom() & 0x7fff
    let error = nzRandom()

    // good operand, good transform
    let o1 = Deferred(value: value)
    let t1 = Deferred { i throws in Double(value*i) }
    let e1 = expectation(description: "r1")
    let r1 = o1.apply(qos: .utility, transform: t1)
    r1.notify { _ in e1.fulfill() }
    XCTAssert(r1.value == Double(value*value))
    XCTAssert(r1.error == nil)

    // bad operand, transform not applied
    let o2 = Deferred<Int> { throw TestError(error) }
    let t2 = Deferred { (i:Int) throws -> Float in XCTFail(); return Float(i) }
    let e2 = expectation(description: "r2")
    let r2 = o2.apply(transform: t2)
    r2.notify { _ in e2.fulfill() }
    XCTAssert(r2.value == nil)
    XCTAssert(r2.error as? TestError == TestError(error))

    waitForExpectations(timeout: 1.0)
  }

  func testApply3()
  {
    let value = nzRandom() & 0x7fff
    let error = nzRandom()

    // good operand, bad transform
    let o3 = Deferred(value: value)
    let t3 = Deferred<(Int) throws -> Float>(error: TestError(error))
    let e3 = expectation(description: "r3")
    let r3 = o3.apply(transform: t3)
    r3.notify { _ in e3.fulfill() }
    XCTAssert(r3.value == nil)
    XCTAssert(r3.error as? TestError == TestError(error))

    // good operand, transform throws
    let o4 = Deferred(value: value)
    let t4 = Deferred { (i:Int) throws -> Float in throw TestError(error) }
    let e4 = expectation(description: "r4")
    let r4 = o4.apply(transform: t4)
    r4.notify { _ in e4.fulfill() }
    XCTAssert(r4.value == nil)
    XCTAssert(r4.error as? TestError == TestError(error))

    // result canceled before transform is determined
    let o5 = Deferred(value: value)
    let t5 = TBD<(Int) throws -> Float>()
    let e5 = expectation(description: "r5")
    let r5 = o5.apply(transform: t5)
    combine(t5,r5).notify { _ in e5.fulfill() }
    r5.cancel()
    t5.determine({ Float($0) })
    XCTAssert(r5.value == nil)
    XCTAssert(r5.error as? DeferredError == DeferredError.canceled(""))

    waitForExpectations(timeout: 1.0)
  }

  func testQoS()
  {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    let q = DispatchQueue.global(qos: .utility)
    let qb = Deferred(queue: q, task: { qos_class_self() }).enqueuing(at: .background, serially: false)
    // Verify that the block's QOS was adjusted and is different from the queue's
    XCTAssert(qb.value == QOS_CLASS_UTILITY)
    XCTAssert(qb.qos == DispatchQoS.background)

    let e1 = expectation(description: "e1")
    let q1 = Deferred(qos: .background, value: qos_class_self())
    q1.onValue {
      qosv in
      // Verify that the QOS has been adjusted
      XCTAssert(qosv != qos_class_self())
      XCTAssert(qos_class_self() == QOS_CLASS_BACKGROUND)
      e1.fulfill()
    }

    let e2 = expectation(description: "e2")
    let q2 = qb.enqueuing(at: .background, serially: true)
    q2.notify { _ in e2.fulfill() }

    let e3 = expectation(description: "e3")
    let q3 = q2.map(qos: .userInitiated) {
      qosv -> qos_class_t in
      XCTAssert(qosv == QOS_CLASS_UTILITY)
      // Verify that the QOS has changed
      XCTAssert(qosv != qos_class_self())
      // This block is running at the requested QOS
      XCTAssert(qos_class_self() == QOS_CLASS_USER_INITIATED)
      e3.fulfill()
      return qos_class_self()
    }

    let e4 = expectation(description: "e4")
    let q4 = q3.enqueuing(at: .userInteractive)
    q4.onValue {
      qosv in
      // Last block was in fact executing at QOS_CLASS_USER_INITIATED
      XCTAssert(qosv == QOS_CLASS_USER_INITIATED)
      // Last block wasn't executing at the queue's QOS
      XCTAssert(qosv != QOS_CLASS_BACKGROUND)
      // This block is executing at the queue's QOS.
      XCTAssert(qos_class_self() == QOS_CLASS_USER_INTERACTIVE)
      XCTAssert(qos_class_self() != QOS_CLASS_BACKGROUND)
      e4.fulfill()
    }

    waitForExpectations(timeout: 1.0)
#else
    print("testQoS() not implemented for swift-corelibs-dispatch platforms")
#endif
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
    let d2 = Deferred(value: nzRandom())
    XCTAssert(d2.cancel("message") == false)

    if let e = d1.error as? DeferredError
    {
      XCTAssert(e.description != "")
      XCTAssert(e == DeferredError.canceled(""))
    }
  }

  func testCancelAndNotify()
  {
    let tbd = TBD<Int>()

    let d1 = tbd.map { $0 * 2 }
    let e1 = expectation(description: "first deferred")
    d1.onValue { _ in XCTFail() }
    d1.notify  { r in XCTAssert(r.error != nil) }
    d1.onError {
      if $0 as? DeferredError == DeferredError.canceled("test") { e1.fulfill() }
    }

    let d2 = d1.map  { $0 + 100 }
    let e2 = expectation(description: "second deferred")
    d2.onValue { _ in XCTFail() }
    d2.notify  { r in XCTAssert(r.error != nil) }
    d2.onError {
      if $0 as? DeferredError == DeferredError.canceled("test") { e2.fulfill() }
    }

    d1.cancel("test")

    waitForExpectations(timeout: 1.0) { _ in tbd.cancel() }
  }

  func testCancelMap()
  {
    let tbd = TBD<Int>()

    let e1 = expectation(description: "cancellation of Deferred.map, part 1")
    let d1 = tbd.map { u in XCTFail(String(u)) }
    d1.onError { e in e1.fulfill() }
    XCTAssert(d1.cancel() == true)

    let e2 = expectation(description: "cancellation of Deferred.map, part 2")
    let d2 = tbd.map(transform: { u in XCTFail(String(u)) }).enqueuing(at: .background)
    d2.onError { e in e2.fulfill() }
    XCTAssert(d2.cancel() == true)

    tbd.determine(numericCast(nzRandom()))

    waitForExpectations(timeout: 1.0)
  }

  func testCancelDelay()
  {
    let tbd = TBD<Int>()

    let e1 = expectation(description: "cancellation of Deferred.delay")
    let d1 = tbd.delay(.milliseconds(100))
    d1.onError { e in e1.fulfill() }
    XCTAssert(d1.cancel() == true)

    tbd.determine(numericCast(nzRandom()))

    waitForExpectations(timeout: 1.0)
  }

  func testCancelBind()
  {
    let tbd = TBD<Int>()

    let e1 = expectation(description: "cancellation of Deferred.flatMap")
    let d1 = tbd.flatMap { Deferred(value: $0) }
    d1.onError { e in e1.fulfill() }
    XCTAssert(d1.cancel() == true)

    let e2 = expectation(description: "cancellation of Deferred.recover")
    let d2 = tbd.recover { i in Deferred(value: Int.max) }
    d2.onError { e in e2.fulfill() }
    XCTAssert(d2.cancel() == true)

    let e3 = expectation(description: "cancellation of Deferred.flatMap, part 2")
    let d3 = tbd.flatMap(transform: { Deferred(value: $0) }).map(transform: { Double($0) })
    d3.onError { e in e3.fulfill() }
    XCTAssert(d3.cancel() == true)

    let e4 = expectation(description: "cancellation of Deferred.recover, part 2")
    let d4 = tbd.recover(transform: { e in Deferred(value: Int.min) }).map(transform: { $0/2 })
    d4.onError { e in e4.fulfill() }
    XCTAssert(d4.cancel() == true)

    tbd.determine(numericCast(nzRandom()))

    waitForExpectations(timeout: 1.0)
  }

  func testCancelApply()
  {
    let tbd = TBD<Int>()

    let e1 = expectation(description: "cancellation of Deferred.apply, part 1")
    let t1 = Deferred { (i: Int) throws in Double(i) }
    let d1 = tbd.apply(transform: t1)
    d1.onError { e in e1.fulfill() }

    let e2 = expectation(description: "cancellation of Deferred.apply, part 2")
    let t2 = t1.delay(.milliseconds(100))
    let d2 = Deferred(value: 1).apply(transform: t2)
    d2.onError { e in e2.fulfill() }

    let e3 = expectation(description: "cancellation of Deferred.apply, part 3")
    let t3 = Deferred { (i: Int) in Double(i) }
    let d3 = tbd.apply(transform: t3).map(transform: { 2*$0} )
    d3.onError { e in e3.fulfill() }

    let e4 = expectation(description: "cancellation of Deferred.apply, part 4")
    let t4 = t3.delay(.milliseconds(100))
    let d4 = Deferred(value: 1).apply(transform: t4)
    d4.onError { e in e4.fulfill() }

    usleep(1000)
    XCTAssert(d1.cancel() == true)
    XCTAssert(d2.cancel() == true)
    XCTAssert(d3.cancel() == true)
    XCTAssert(d4.cancel() == true)

    tbd.determine(numericCast(nzRandom()))

    waitForExpectations(timeout: 1.0)
  }

  func testValidate1()
  {
    let d = (0..<10).map({Deferred.init(value:$0)})
    let m = String(nzRandom())

    let v = d.map({ $0.validate(qos: .background, predicate: { $0%2 == 0 }, message: m) })
    let e = v.flatMap { $0.error }
    XCTAssert(e.count == d.count/2)
    XCTAssertEqual(e.first as? DeferredError, DeferredError.invalid(m))
  }

  func testValidate2()
  {
    let d = (0..<10).map({Deferred.init(value:$0)})
    let i = nzRandom()

    let v = d.map({ $0.validate(qos: .utility, predicate: { if $0%2 == 0 { throw TestError(i) } }) })
    let e = v.flatMap { $0.error }
    XCTAssert(e.count == d.count/2)
    XCTAssertEqual(e.first as? TestError, TestError(i))
  }

  func testOptional() throws
  {
    let rnd = nzRandom()

    var opt = rnd as Optional
    let d1 = opt.deferred()
    XCTAssert(d1.value == rnd)

    opt = nil
    let d2 = opt.deferred()
    do {
      _ = try d2.get()
      XCTFail()
    }
    catch DeferredError.invalid {}
  }

  func testDeferredError()
  {
    let customMessage = "Custom Message"

    let errors: [DeferredError] = [
      .canceled(""),
      .canceled(customMessage),
      .invalid(""),
      .invalid(customMessage),
      .timedOut(""),
      .timedOut(customMessage),
    ]

    let strings = errors.map(String.init(describing: ))
    // strings.forEach({print($0)})

    for (i,e) in errors.enumerated()
    {
      XCTAssert(String(describing: e) == strings[i])
      errors.enumerated().forEach {
        index, error in
        XCTAssert((error == e) == (index == i))
      }
    }
  }

  func testTimeout()
  {
    let d1 = Deferred(value: 1).delay(.milliseconds(100))
    let e1 = expectation(description: "Timeout test 1: instant timeout")
    d1.onValue { _ in XCTFail() }
    d1.onError { _ in e1.fulfill() }
    d1.timeout(.seconds(-1))

    let s2 = DispatchTime.now()
    let t2 = 0.15
    let m2 = String(nzRandom())
    let d2 = Deferred(value: 1).delay(.seconds(5))
    let e2 = expectation(description: "Timeout test 2: times out")
    d2.onValue { _ in XCTFail() }
    d2.onError {
      error in
      XCTAssert(s2 + t2 <= .now())
      if error as? DeferredError == DeferredError.timedOut(m2) { e2.fulfill() }
    }
    d2.timeout(seconds: t2, reason: m2)

    let t3 = 0.05
    let d3 = Deferred(value: DispatchTime.now()).delay(seconds: t3)
    let e3 = expectation(description: "Timeout test 3: determine before timeout")
    d3.onValue { time in if time + t3 <= .now() { e3.fulfill() } }
    d3.onError { _ in XCTFail() }
    d3.timeout(seconds: 5*t3)

    let t4 = 0.2
    let d4 = Deferred(value: DispatchTime.now()).delay(seconds: t4)
    let e4 = expectation(description: "Timeout test 4: never timeout")
    d4.onValue { time in if time + t4 <= .now() { e4.fulfill() } }
    d4.onError { _ in XCTFail() }
    d4.timeout(after: .distantFuture)

    waitForExpectations(timeout: 1.0)

    d4.timeout(after: .distantFuture)
  }
}
