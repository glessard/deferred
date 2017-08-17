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

#if SWIFT_PACKAGE
  import syncprint
  import Atomics
#endif

import deferred


class DeferredTests: XCTestCase
{
  static var allTests: [(String, (DeferredTests) -> () throws -> Void)] {
    return [
      ("testExample", testExample),
      ("testExample2", testExample2),
      ("testExample3", testExample3),
      ("testDelay", testDelay),
      ("testValue", testValue),
      ("testPeek", testPeek),
      ("testValueBlocks", testValueBlocks),
      ("testValueUnblocks", testValueUnblocks),
      ("testNotify1", testNotify1),
      ("testNotify2", testNotify2),
      ("testNotify3", testNotify3),
      ("testNotify4", testNotify4),
      ("testMap", testMap),
      ("testMap2", testMap2),
      ("testRecover", testRecover),
      ("testFlatMap", testFlatMap),
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
    ]
  }

  func testExample()
  {
    syncprint("Starting")

    let result1 = Deferred(qos: .background) {
      () -> Double in
      defer { syncprint("Computing result1") }
      return 10.5
    }.delay(.milliseconds(50))

    let result2 = result1.map {
      (d: Double) -> Int in
      syncprint("Computing result2")
      return Int(floor(2*d))
    }.delay(.milliseconds(500))

    let result3 = result1.map {
      (d: Double) -> String in
      syncprint("Computing result3")
      return (3*d).description
    }

    result3.notify { syncprint($0) }

    let result4 = combine(result1, result2)

    let result5 = result2.map(transform: Double.init).timeout(.milliseconds(50))

    syncprint("Waiting")
    syncprint("Result 1: \(result1.result)")
    syncprint("Result 2: \(result2.result)")
    syncprint("Result 3: \(result3.result)")
    syncprint("Result 4: \(result4.result)")
    syncprint("Result 5: \(result5.result)")
    syncprint("Done")
    syncprintwait()

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
    let interval = 0.1
    let d1 = Deferred(Result.value(Date()))
    let delayed1 = d1.delay(seconds: interval)
    let d2 = delayed1.map { Date().timeIntervalSince($0) }

    XCTAssert(d2.value! >= interval)
    XCTAssert(d2.value! < 2.0*interval)

    // a negative delay returns the same reference
    let d3 = d1.delay(seconds: -0.001)
    XCTAssert(d3 === d1)

    let delayed2 = d1.delay(.microseconds(-1))
    let d4 = delayed2.map { $0 }
    XCTAssert(d4.value == d3.value)

    // a longer calculation is not delayed (significantly)
    let d5 = Deferred<Date> {
      Thread.sleep(forTimeInterval:interval)
      return Date()
    }
    let delayed3 = d5.delay(seconds: interval/10)
    let d6 = delayed3.map { Date().timeIntervalSince($0) }
    let actualDelay = d6.delay(.nanoseconds(100)).value
    XCTAssert(actualDelay! < interval/10)

#if swift(>=3.2) && !os(Linux)
    // an unreasonable delay
    let d7 = Deferred(value: Date())
    let d8 = d7.delay(.never)
    let d9 = d7.delay(.milliseconds(10))
    XCTAssert((d9.value ?? Date.distantFuture) <= Date())
    XCTAssert(d8.state != .determined)
    d8.cancel()
    XCTAssert(d8.state == .determined)
    XCTAssert(d8.value == nil)
#elseif os(Linux)
    // FIXME: delay(.never) on Linux
    print("TODO: identify issue related to DispatchTimeInterval.never on Linux")
#endif
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
    XCTAssert(d1.peek()! == Result.value(value))

    let d2 = d1.delay(.microseconds(10_000))
    XCTAssert(d2.peek() == nil)
    XCTAssert(d2.isDetermined == false)

    _ = d2.value // Wait for delay

    XCTAssert(d2.peek() != nil)
    XCTAssert(d2.peek()! == Result.value(value))
    XCTAssert(d2.isDetermined)
  }

  func testValueBlocks()
  {
    let wait = 0.1

    let value = nzRandom()

    let s = DispatchSemaphore(value: 0)
    let busy = Deferred<UInt32> {
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
    let busy = Deferred<UInt32> {
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

  func testNotify1()
  {
    let value = nzRandom()
    let e1 = expectation(description: "Pre-set Deferred")
    let d1 = Deferred(value: value)
    d1.notify {
      XCTAssert( $0 == Result.value(value) )
      e1.fulfill()
    }
    waitForExpectations(timeout: 1.0)
  }

  func testNotify2()
  {
    let value = nzRandom()
    let e2 = expectation(description: "Properly Deferred")
    let d1 = Deferred(value: value)
    let d2 = d1.delay(.milliseconds(100))
    let q3 = DispatchQueue(label: "Test", qos: .background)
    let d3 = d2.notifying(on: q3)
    d3.notify(qos: .utility) {
      XCTAssert( $0 == Result.value(value) )
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
      result in
      guard case let .error(e) = result,
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

  func testMap2()
  {
    let value = nzRandom()
    let error = nzRandom()
    let goodOperand = Deferred(value: value)
    let badOperand  = Deferred<Double>(error: TestError(error))

    // good operand, good transform
    let d1 = goodOperand.map { Result.value(Int($0)*2) }
    XCTAssert(d1.value == Int(value)*2)
    XCTAssert(d1.error == nil)

    // good operand, transform errors
    let d2 = goodOperand.map { Result<Void>.error(TestError($0)) }
    XCTAssert(d2.value == nil)
    XCTAssert(d2.error as? TestError == TestError(value))

    // bad operand, transform short-circuited
    let d3 = badOperand.map { _ in Result<Void> { XCTFail() } }
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
    do {
      _ = try r4.result.getValue()
      XCTFail()
    }
    catch DeferredError.canceled(let message) { XCTAssert(message == reason) }
    catch { XCTFail() }
  }

  func testFlatMap()
  {
    let value = nzRandom()
    let error = nzRandom()
    let goodOperand = Deferred(value: value)
    let badOperand  = Deferred<Double>(error: TestError(error))

    // good operand, good transform
    let d1 = goodOperand.flatMap { Deferred(value: Int($0)*2) }
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
    let result = operand.apply(transform: transform)
    let expect = expectation(description: "Applying a deferred transform to a deferred operand")

    var v1 = 0
    var v2 = 0
    result.notify {
      result in
      print("\(v1), \(v2), \(result)")
      XCTAssert(result == Result.value(Double(v1*v2)))
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

    XCTAssert(operand.peek() == nil)
    XCTAssert(operand.state == .waiting)
    XCTAssert(transform.peek() == nil)
    XCTAssert(transform.state == .waiting)

    g.determine(0)
    waitForExpectations(timeout: 1.0)

    XCTAssert(transform.state == .determined)
  }

  func testApply2()
  {
    let value = Int(nzRandom() & 0x7fff + 10000)
    let error = nzRandom()

    // good operand, good transform
    let o1 = Deferred(value: value)
    let t1 = Deferred { i throws in Double(value*i) }
    let e1 = expectation(description: "r1")
    let r1 = o1.apply(transform: t1)
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
    let value = Int(nzRandom() & 0x7fff + 10000)
    let error = nzRandom()

    // good operand, good transform
    let o1 = Deferred(value: value)
    let t1 = Deferred { i in Result.value(Double(value*i)) }
    let e1 = expectation(description: "r1")
    let r1 = o1.apply(transform: t1)
    r1.notify { _ in e1.fulfill() }
    XCTAssert(r1.value == Double(value*value))
    XCTAssert(r1.error == nil)

    // bad operand, transform not applied
    let o2 = Deferred<Int> { throw TestError(error) }
    let t2 = Deferred { (i:Int) in Result<Float> { XCTFail(); return Float(i) } }
    let e2 = expectation(description: "r2")
    let r2 = o2.apply(transform: t2)
    r2.notify { _ in e2.fulfill() }
    XCTAssert(r2.value == nil)
    XCTAssert(r2.error as? TestError == TestError(error))

    waitForExpectations(timeout: 1.0)
  }

  func testQoS()
  {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    let q = DispatchQueue.global(qos: .background)
    let qb = Deferred(queue: q, qos: .utility) { qos_class_self() }
    // Verify that the block's QOS was adjusted and is different from the queue's
    XCTAssert(qb.value == QOS_CLASS_UTILITY)
    XCTAssert(qb.qos == DispatchQoS.background)

    let e1 = expectation(description: "e1")
    let q1 = Deferred(qos: .background, result: Result.value(qos_class_self()))
    q1.onValue {
      qosv in
      // Verify that the QOS has been adjusted
      XCTAssert(qosv != qos_class_self())
      XCTAssert(qos_class_self() == QOS_CLASS_BACKGROUND)
      e1.fulfill()
    }

    let e2 = expectation(description: "e2")
    let q2 = qb.notifying(at: .background, serially: true)
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
    let q4 = q3.notifying(at: .userInteractive)
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
    let d1 = Deferred(qos: .utility) {
      () -> UInt32 in
      usleep(100_000)
      return nzRandom()
    }

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
      e in
      guard let de = e as? DeferredError else { fatalError() }
      guard case .canceled(let m) = de, m == "test" else { fatalError() }
      e1.fulfill()
    }

    let d2 = d1.map  { $0 + 100 }
    let e2 = expectation(description: "second deferred")
    d2.onValue { _ in XCTFail() }
    d2.notify  { r in XCTAssert(r.error != nil) }
    d2.onError {
      e in
      guard let de = e as? DeferredError else { fatalError() }
      guard case .canceled(let m) = de, m == "test" else { fatalError() }
      e2.fulfill()
    }

    d1.cancel("test")

    waitForExpectations(timeout: 1.0) { _ in tbd.cancel() }
  }

  func testCancelMap()
  {
    let tbd = TBD<Int>()

    let e1 = expectation(description: "cancellation of Deferred.map(_: U throws -> T)")
    let d1 = tbd.map { u throws in XCTFail(String(u)) }
    d1.onError { e in e1.fulfill() }
    XCTAssert(d1.cancel() == true)

    let e2 = expectation(description: "cancellation of Deferred.map(_: U -> Result<T>)")
    let d2 = tbd.map { u in Result.value(XCTFail(String(u))) }
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
    XCTAssert(d1.cancel() == true)

    let e2 = expectation(description: "cancellation of Deferred.apply, part 2")
    let t2 = t1.delay(.milliseconds(100))
    let d2 = Deferred(value: 1).apply(transform: t2)
    d2.onError { e in e2.fulfill() }
    usleep(1000)
    XCTAssert(d2.cancel() == true)

    let e3 = expectation(description: "cancellation of Deferred.apply, part 3")
    let t3 = Deferred { (i: Int) in Result.value(Double(i)) }
    let d3 = tbd.apply(transform: t3)
    d3.onError { e in e3.fulfill() }
    XCTAssert(d3.cancel() == true)

    let e4 = expectation(description: "cancellation of Deferred.apply, part 2")
    let t4 = t3.delay(.milliseconds(100))
    let d4 = Deferred(value: 1).apply(transform: t4)
    d4.onError { e in e4.fulfill() }
    usleep(1000)
    XCTAssert(d4.cancel() == true)

    tbd.determine(numericCast(nzRandom()))

    waitForExpectations(timeout: 1.0)
  }

  func testTimeout()
  {
    let value = nzRandom()
    let d = Deferred(value: value)

    let d1 = d.timeout(.milliseconds(5))
    XCTAssert(d1.value == value)

    let d2 = d.delay(.seconds(5)).timeout(.milliseconds(2))
    let e2 = expectation(description: "Timeout test")
    d2.onValue { _ in XCTFail() }
    d2.onError { _ in e2.fulfill() }

    let d3 = d.delay(.milliseconds(100)).timeout(.seconds(-1))
    let e3 = expectation(description: "Unreasonable timeout test")
    d3.onValue { _ in XCTFail() }
    d3.onError { _ in e3.fulfill() }

    let d4 = d.delay(.milliseconds(50)).timeout(seconds: 0.5)
    let e4 = expectation(description: "Timeout test 4")
    d4.onValue { _ in e4.fulfill() }
    d4.onError { _ in XCTFail() }

    let d5 = TBD<Double>()
    let e5 = expectation(description: "Timeout test 5")
    d5.onValue { _ in XCTFail() }
    d5.onError { _ in e5.fulfill() }
    _ = d5.timeout(.microseconds(1))

#if swift(>=3.2)
    let d6 = TBD<Double>()
    let t6 = d6.timeout(.never)
    XCTAssert(d6 === t6)
#endif

    waitForExpectations(timeout: 1.0)
  }
}
