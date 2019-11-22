//
//  DeferredExtrasTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 11/21/19.
//  Copyright © 2019 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation
import Dispatch

import deferred

class DeferredExtrasTests: XCTestCase
{
  func testOnResolution1()
  {
    let value = nzRandom()
    let e1 = expectation(description: "Pre-set Deferred")
    let d1 = Deferred<Int, Never>(value: value)
    d1.onResult {
      result in
      XCTAssertEqual(result.value, value)
      e1.fulfill()
    }
    waitForExpectations(timeout: 1.0)
  }

  func testOnResolution2()
  {
    let value = nzRandom()
    let e2 = expectation(description: "Properly Deferred")
    let d1 = Deferred<Int, Never>(qos: .background, value: value)
    let d2 = d1.delay(.milliseconds(100))
    d2.onResult(queue: DispatchQueue(label: "Test", qos: .utility)) {
      result in
      XCTAssertEqual(result.value, value)
      e2.fulfill()
    }
    waitForExpectations(timeout: 1.0)
  }

  func testOnResolution3()
  {
    let e3 = expectation(description: "Pre-set Deferred Error")
    let d3 = Deferred<Int, Cancellation>(error: .canceled(""))
    d3.onResult {
      result in
      XCTAssertEqual(result.error, .canceled(""))
      e3.fulfill()
    }
    waitForExpectations(timeout: 1.0)
  }

  func testOnValueAndOnError()
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

    // bad operand, transform throws (type 1)
    let d2 = badOperand.recover { error in Deferred { throw TestError(value) } }
    XCTAssert(d2.value == nil)
    XCTAssert(d2.error as? TestError == TestError(value))

    // bad operand, transform throws (type 2)
    let d5 = badOperand.recover { _ in throw TestError(value) }
    XCTAssert(d5.value == nil)
    XCTAssert(d5.error as? TestError == TestError(value))

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

  func testRetrying1()
  {
    let retries = 5
    let queue = DispatchQueue(label: "test")

    let r1 = Deferred.Retrying(0, queue: queue, task: { Deferred<Void>(task: {XCTFail()}) })
    if let e = r1.error as? DeferredError,
       case .invalid(let s) = e
    { _ = s } // print(s)
    else { XCTFail() }

    var counter = 0
    let r2 = Deferred.Retrying(retries, queue: queue) {
      () -> Deferred<Int> in
      counter += 1
      if counter < retries { return Deferred(error: TestError(counter)) }
      return Deferred(value: counter)
    }
    XCTAssert(r2.value == retries)
  }

  func testRetrying2()
  {
    let retries = 5

    let r1 = Deferred.Retrying(0, task: { Deferred<Void>(task: {XCTFail()}) })
    if let e = r1.error as? DeferredError,
      case .invalid(let s) = e
    { _ = s } // print(s)
    else { XCTFail() }

    var counter = 0
    let r2 = Deferred.Retrying(retries) {
      () -> Deferred<Int> in
      counter += 1
      if counter < retries { return Deferred(error: TestError(counter)) }
      return Deferred(value: counter)
    }
    XCTAssert(r2.value == retries)

    let r3 = Deferred.Retrying(retries, qos: .background) {
      () -> Deferred<Int> in
      counter += 1
      return Deferred(error: TestError(counter))
    }
    XCTAssert(r3.error as? TestError == TestError(2*retries))
  }

  func testRetryTask()
  {
    let retries = 5
    let queue = DispatchQueue(label: "test", qos: .background)

    var counter = 0
    let r1 = Deferred.RetryTask(retries, queue: queue) {
      () in
      counter += 1
      throw TestError(counter)
    }
    XCTAssert(r1.value == nil)
    XCTAssert(r1.error as? TestError == TestError(retries))
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    XCTAssert(r1.qos == .background)
#endif

    let r2 = Deferred.RetryTask(retries, qos: .utility) {
      counter += 1
      throw TestError(counter)
    }
    XCTAssert(r2.value == nil)
    XCTAssert(r2.error as? TestError == TestError(2*retries))
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    XCTAssert(r2.qos == .utility)
#endif
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

    let (t3, dv3) = TBD<Deferred<Int>>.CreatePair()
    let d3 = dv3.flatten()
    let e3 = expectation(description: "flatten, part 3")
    d3.validate(predicate: { XCTAssertEqual($0, value) }).onValue(task: { _ in e3.fulfill() })
    t3.resolve(value: Deferred(value: value))

    let (t4, dv4) = TBD<Deferred<Int>>.CreatePair()
    let d4 = dv4.flatten()
    let e4 = expectation(description: "flatten, part 4")
    d4.recover(transform: { Deferred(error: $0) }).onError(task: { _ in e4.fulfill() })
    t4.resolve(error: TestError(error))

    let (t5, dv5) = TBD<Int>.CreatePair()
    let fullyDeferred = Deferred(value: dv5.delay(seconds: 0.02)).delay(seconds: 0.01)
    let d5 = fullyDeferred.flatten()
    let e5 = expectation(description: "flatten, part 5")
    d5.validate(predicate: { XCTAssertEqual($0, value) }).onValue(task: { _ in e5.fulfill() })

    let semiDeferred = Deferred(value: dv5.delay(seconds: 0.01))
    let d6 = semiDeferred.flatten()
    let e6 = expectation(description: "flatten, part 6")
    d6.validate(predicate: { XCTAssertEqual($0, value) }).onValue(task: { _ in e6.fulfill() })

//    let willCompile = Deferred(value: d1).flatten()
//    let wontCompile = Deferred(value: 99).flatten()

    t5.resolve(value: value)

    waitForExpectations(timeout: 1.0)
  }

  func testEnqueuing()
  {
    let r1 = nzRandom()
    let r2 = nzRandom()

    let transferred1 = Deferred(value: r1).enqueuing(on: DispatchQueue.global())

    let (t, d) = TBD<Int>.CreatePair(qos: .background)
    let transferred2 = d.enqueuing(at: .userInitiated, serially: false)
    t.resolve(value: r2)

    XCTAssert(transferred1.value == r1)
    XCTAssert(transferred2.value == r2)
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
    let q1 = Deferred<qos_class_t, Never>(qos: .background, value: qos_class_self())
    q1.onValue {
      qosv in
      // Verify that the QOS has been adjusted
      XCTAssert(qosv != qos_class_self())
      XCTAssert(qos_class_self() == QOS_CLASS_BACKGROUND)
      e1.fulfill()
    }

    let e2 = expectation(description: "e2")
    let q2 = qb.enqueuing(at: .background, serially: true)
    q2.onResult { _ in e2.fulfill() }

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
    let (t, transform) = TBD<(Int) -> Double>.CreatePair()
    let (o, operand) = TBD<Int>.CreatePair()
    let result = operand.apply(qos: .background, transform: transform)
    let expect = expectation(description: "Applying a deferred transform to a deferred operand")

    var v1 = 0
    var v2 = 0
    result.onResult {
      result in
      XCTAssert(result.value == (Double(v1*v2)))
      expect.fulfill()
    }

    let trigger = TBD<Int>() { _ in }

    trigger.onResult { _ in
      v1 = Int(nzRandom() & 0x7fff + 10000)
      t.resolve(value: { i in Double(v1*i) })
    }

    trigger.onResult { _ in
      v2 = Int(nzRandom() & 0x7fff + 10000)
      o.resolve(value: v2)
    }

    XCTAssertFalse(operand.isResolved)
    XCTAssert(operand.state == .waiting)
    XCTAssertFalse(transform.isResolved)
    XCTAssert(transform.state == .waiting)

    trigger.cancel()
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
    r1.onResult { _ in e1.fulfill() }
    XCTAssert(r1.value == Double(value*value))
    XCTAssert(r1.error == nil)

    // bad operand, transform not applied
    let o2 = Deferred<Int> { throw TestError(error) }
    let t2 = Deferred { (i:Int) throws -> Float in XCTFail(); return Float(i) }
    let e2 = expectation(description: "r2")
    let r2 = o2.apply(transform: t2)
    r2.onResult { _ in e2.fulfill() }
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
    r3.onResult { _ in e3.fulfill() }
    XCTAssert(r3.value == nil)
    XCTAssert(r3.error as? TestError == TestError(error))

    // good operand, transform throws
    let o4 = Deferred(value: value)
    let t4 = Deferred { (i:Int) throws -> Float in throw TestError(error) }
    let e4 = expectation(description: "r4")
    let r4 = o4.apply(transform: t4)
    r4.onResult { _ in e4.fulfill() }
    XCTAssert(r4.value == nil)
    XCTAssert(r4.error as? TestError == TestError(error))

    // result canceled before transform is resolved
    let o5 = Deferred(value: value)
    let (t5, d5) = TBD<(Int) throws -> Float>.CreatePair()
    let e5 = expectation(description: "r5")
    let r5 = o5.apply(transform: d5)
    combine(d5, r5).onResult { _ in e5.fulfill() }
    r5.cancel()
    t5.resolve(value: { Float($0) })
    XCTAssert(r5.value == nil)
    XCTAssert(r5.error as? DeferredError == DeferredError.canceled(""))

    waitForExpectations(timeout: 1.0)
  }

  func testCancelAndNotify()
  {
    let (_, tbd) = TBD<Int>.CreatePair()

    let d1 = tbd.map { $0 * 2 }
    let e1 = expectation(description: "first deferred")
    d1.onValue { _ in XCTFail() }
    d1.onResult  { r in XCTAssert(r.error != nil) }
    d1.onError {
      if $0 as? DeferredError == DeferredError.canceled("test") { e1.fulfill() }
    }

    let d2 = d1.map  { $0 + 100 }
    let e2 = expectation(description: "second deferred")
    d2.onValue { _ in XCTFail() }
    d2.onResult  { r in XCTAssert(r.error != nil) }
    d2.onError {
      if $0 as? DeferredError == DeferredError.canceled("test") { e2.fulfill() }
    }

    d1.cancel("test")

    waitForExpectations(timeout: 1.0) { _ in tbd.cancel() }
  }

  func testCancelMap()
  {
    let (t0, d0) = TBD<Int>.CreatePair()

    let e1 = expectation(description: "cancellation of Deferred.map, part 1")
    let d1 = d0.map { XCTFail(String($0)) }
    d1.onError { e in e1.fulfill() }
    XCTAssert(d1.cancel() == true)

    let e2 = expectation(description: "cancellation of Deferred.map, part 2")
    let d2 = d0.map(transform: { $0+1 }).map(transform: { XCTFail(String($0)) })
    d2.onError { e in e2.fulfill() }
    XCTAssert(d2.cancel() == true)

    t0.resolve(value: numericCast(nzRandom()))

    waitForExpectations(timeout: 1.0)
  }

  func testCancelDelay()
  {
    let (t0, d0) = TBD<Int>.CreatePair()

    let e1 = expectation(description: "cancellation of Deferred.delay")
    let d1 = d0.delay(.milliseconds(100))
    d1.onError { e in e1.fulfill() }
    XCTAssert(d1.cancel() == true)

    t0.resolve(value: numericCast(nzRandom()))

    waitForExpectations(timeout: 1.0)
  }

  func testCancelFlatMap()
  {
    let (t0, d0) = TBD<Int>.CreatePair()

    let e1 = expectation(description: "cancellation of Deferred.flatMap")
    let d1 = d0.flatMap { Deferred(value: $0) }
    d1.onError { e in e1.fulfill() }
    XCTAssert(d1.cancel() == true)

    let e3 = expectation(description: "cancellation of Deferred.flatMap, part 2")
    let d3 = d0.flatMap(transform: { Deferred(value: $0) }).map(transform: { Double($0) })
    d3.onError { e in e3.fulfill() }
    XCTAssert(d3.cancel() == true)

    t0.resolve(value: numericCast(nzRandom()))

    waitForExpectations(timeout: 1.0)
  }

  func testCancelRecover()
  {
    let (t0, d0) = TBD<Int>.CreatePair()

    let e2 = expectation(description: "cancellation of Deferred.recover")
    let d2 = d0.recover { i in Deferred(value: Int.max) }
    d2.onError { e in e2.fulfill() }
    XCTAssert(d2.cancel() == true)

    let e4 = expectation(description: "cancellation of Deferred.recover, part 2")
    let d4 = d0.recover(transform: { e in Deferred(value: Int.min) }).map(transform: { $0/2 })
    d4.onError { e in e4.fulfill() }
    XCTAssert(d4.cancel() == true)

    t0.resolve(value: numericCast(nzRandom()))

    waitForExpectations(timeout: 1.0)
  }

  func testCancelApply()
  {
    let (t0, d0) = TBD<Int>.CreatePair()

    let e1 = expectation(description: "cancellation of Deferred.apply, part 1")
    let t1 = Deferred { (i: Int) throws in Double(i) }
    let d1 = d0.apply(transform: t1)
    d1.onError { e in e1.fulfill() }

    let e2 = expectation(description: "cancellation of Deferred.apply, part 2")
    let t2 = t1.delay(.milliseconds(100))
    let d2 = Deferred(value: 1).apply(transform: t2)
    d2.onError { e in e2.fulfill() }

    let e3 = expectation(description: "cancellation of Deferred.apply, part 3")
    let t3 = Deferred { (i: Int) in Double(i) }
    let d3 = d0.apply(transform: t3).map(transform: { 2*$0} )
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

    t0.resolve(value: numericCast(nzRandom()))

    waitForExpectations(timeout: 1.0)
  }

  func testValidate1()
  {
    let d = (0..<10).map({Deferred.init(value:$0)})
    let m = String(nzRandom())

    let v = d.map({ $0.validate(qos: .background, predicate: { $0%2 == 0 }, message: m) })
    let e = v.compactMap { $0.error }
    XCTAssert(e.count == d.count/2)
    XCTAssertEqual(e.first as? DeferredError, DeferredError.invalid(m))
  }

  func testValidate2()
  {
    let d = (0..<10).map({Deferred.init(value:$0)})
    let i = nzRandom()

    let v = d.map({ $0.validate(qos: .utility, predicate: { if $0%2 == 0 { throw TestError(i) } }) })
    let e = v.compactMap { $0.error }
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
    let e3 = expectation(description: "Timeout test 3: resolve before timeout")
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

  func testSplit()
  {
    let r2v = nzRandom()
    let d2v = Deferred(value: (r2v, String(r2v)))
    let s2v = d2v.split()
    XCTAssertEqual(s2v.0.value, s2v.1.value.flatMap(Int.init))

    let d2e = Deferred<(Int, String)>(error: TestError(nzRandom()))
    let s2e = d2e.split()
    XCTAssertEqual(s2e.0.error as? TestError, s2e.1.error as? TestError)

    let r3 = nzRandom()
    let d3 = Deferred(value: (r3, Double(r3), String(r3)))
    let s3 = d3.split()
    XCTAssertEqual(s3.0.value.map(Double.init), s3.1.value)
    XCTAssertEqual(s3.0.value.map(String.init), s3.2.value)

    let r4 = nzRandom()
    let d4 = Deferred(value: (r4, r4.magnitude, Double(r4), String(r4)))
    let s4 = d4.split()
    XCTAssertEqual(s4.0.value.map({ $0.magnitude }), s4.1.value)
    XCTAssertEqual(s4.1.value.map(Double.init), s4.2.value.map({ $0.magnitude }))
    XCTAssertEqual(s4.0.value.map(String.init), s4.3.value)
  }
}
