//
//  DeferredExtrasTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 2019-11-21.
//  Copyright © 2019-2020 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation
import Dispatch

import deferred

class DeferredExtrasTests: XCTestCase
{
  func testOnValueAndOnError()
  {
    let d4 = Deferred<Int, TestError>(value: nzRandom())
    let e4 = expectation(description: "Test onValue()")
    d4.onValue { _ in e4.fulfill() }
    d4.onError { _ in XCTFail() }

    let d5 = Deferred<Int, NSError>(error: NSError(domain: "", code: 0))
    let e5 = expectation(description: "Test onError()")
    d5.onValue { _ in XCTFail() }
    d5.onError { _ in e5.fulfill() }

    waitForExpectations(timeout: 1.0)
  }

  func testOnErrorNever()
  {
    let d1 = Deferred<Int, Never> { _ in }
    XCTAssertEqual(d1.state, .waiting)
    d1.onError { _ in XCTFail() }
    XCTAssertEqual(d1.state, .executing)
  }

  func testMap()
  {
    let value = nzRandom()
    let error = nzRandom()
    let goodOperand = Deferred<Int, Never>(value: value)
    let badOperand = Deferred<Int, TestError>(error: TestError(error))

    // good operand, transform executes
    let d1 = goodOperand.map { $0*2 }
    XCTAssertEqual(d1.value, value*2)
    XCTAssertEqual(d1.error, nil)

    // bad operand, transform short-circuited
    let d2 = badOperand.map(qos: .utility) { _ in fatalError() }
    XCTAssertEqual(d2.value, nil)
    XCTAssertEqual(d2.error, TestError(error))
  }

  func testTryMap()
  {
    let value = nzRandom()
    let d0 = Deferred<Int, Error>(value: value)

    // good operand, good transform
    let d1 = d0.tryMap { $0*2 }

    // good operand, transform throws
    let d2 = d1.tryMap { i throws -> Double in throw TestError(i) }

    // bad operand, transform short-circuited
    let d3 = d2.tryMap(qos: .default) { _ -> Int in fatalError(#function) }

    // FIXME: un-comment this once on-demand execution is reinstated
    // XCTAssertEqual(d1.state, .waiting)
    // XCTAssertEqual(d2.state, .waiting)
    // XCTAssertEqual(d3.state, .waiting)
    XCTAssertEqual(d3.value, nil)
    XCTAssertEqual(d2.state, .resolved)
    XCTAssertEqual(d1.state, .resolved)
    XCTAssertEqual(d3.error, TestError(value*2))
    XCTAssertEqual(d2.value, nil)
    XCTAssertEqual(d2.error, TestError(value*2))
    XCTAssertEqual(d1.value, value*2)
    XCTAssertEqual(d1.error, nil)
  }

  func testMapError()
  {
    let value = nzRandom()
    let error = nzRandom()
    let goodOperand = Deferred<Int, TestError>(value: value)
    let badOperand  = Deferred<Double, TestError>(error: TestError(error))

    // good operand, transform short-circuited
    let d1 = goodOperand.mapError { _ in fatalError(#function) }
    XCTAssertEqual(d1.value, value)
    XCTAssertEqual(d1.error, nil)

    // bad operand, transform executes
    let d2 = badOperand.mapError(qos: .default) { e in TestError(e.error*2) }
    XCTAssertEqual(d2.value, nil)
    XCTAssertEqual(d2.error, TestError(error*2))

    // bad operand, map to (any) `Error`
    let d3 = badOperand.withAnyError
    XCTAssertEqual(d3.value, nil)
    XCTAssertEqual(d3.error, TestError(error))

    // good operand, map from Never to something else
    let d4 = Deferred<Int, Never>(value: value).setFailureType(to: TestError.self)
    XCTAssertEqual(d4.result, value)
  }

  func testRecover1()
  {
    let value = nzRandom()
    let error = nzRandom()
    let goodOperand = Deferred<Int, Error>(value: value)
    let badOperand  = Deferred<Double, TestError>(error: TestError(error))

    // good operand, transform short-circuited
    let d1 = goodOperand.recover(qos: .default) { _ -> Deferred<Int, Error> in fatalError(#function) }
    XCTAssertEqual(d1.value, value)
    XCTAssertEqual(d1.error, nil)

    // bad operand, transform errors
    let d2 = badOperand.recover { error in Deferred(error: TestError(error.error)) }
    XCTAssertEqual(d2.value, nil)
    XCTAssertEqual(d2.error, TestError(error))

    // bad operand, transform executes later
    let d3 = badOperand.recover { error in Deferred(value: Double(error.error)).delay(.milliseconds(10)) }
    XCTAssertEqual(d3.value, Double(error))
    XCTAssertEqual(d3.error, nil)
  }

  func testRetrying1()
  {
    let retries = 5
    var counter = 0
    let retried = Deferred<Int, TestError>.Retrying(retries, qos: .utility) {
      () -> Deferred<Int, TestError> in
      counter += 1
      if counter < retries { return Deferred(error: TestError(counter)) }
      return Deferred(value: counter)
    }
    XCTAssertEqual(retried.value, retries)

    let errored = Deferred<Int, Error>.Retrying(0, task: { () -> Deferred<Int, Error> in fatalError() })
    XCTAssertEqual(errored.value, nil)
    XCTAssertNotNil(errored.error as? Invalidation)
  }

  func testRecover2()
  {
    let value = nzRandom()
    let error = nzRandom()
    let goodOperand = Deferred<Int, Error>(value: value)
    let badOperand  = Deferred<Double, Error>(error: TestError(error))

    // good operand, transform short-circuited
    let d1 = goodOperand.recover(qos: .default) { _ throws -> Int in fatalError(#function) }
    XCTAssertEqual(d1.value, value)
    XCTAssertEqual(d1.error, nil)

    // bad operand, transform errors
    let d2 = badOperand.recover { try ($0 as? TestError).map { throw TestError($0.error) } ?? 0.0 }
    XCTAssertEqual(d2.value, nil)
    XCTAssertEqual(d2.error, TestError(error))

    // bad operand, transform executes
    let d3 = badOperand.recover { ($0 as? TestError).map { Double($0.error) } ?? 0.0 }
    XCTAssertEqual(d3.value, Double(error))
    XCTAssertEqual(d3.error, nil)
  }

  func testRetrying2()
  {
    let retries = 5
    let queue = DispatchQueue(label: #function, qos: .background)

    var counter = retries+retries-1
    func transform() throws -> Int
    {
      counter -= 1
      guard counter <= 0 else { throw TestError(counter) }
      return counter
    }

    let r1 = Deferred.Retrying(retries, queue: queue, task: transform)
    XCTAssertEqual(r1.value, nil)
    XCTAssertEqual(r1.error, TestError(retries-1))

    let r2 = Deferred.Retrying(retries, qos: .utility, task: transform)
    XCTAssertEqual(r2.value, 0)
    XCTAssertEqual(r2.error, nil)

    let r3 = Deferred.Retrying(0, task: { Double.nan })
    XCTAssertEqual(r3.value, nil)
    XCTAssertNotNil(r3.error as? Invalidation)
  }

  func testFlatMap()
  {
    let value = nzRandom()
    let d0 = Deferred<Int, TestError>(value: value)

    // good operand, transform executes
    let d1 = d0.flatMap(qos: .default) { Deferred<Int, TestError>(value: $0*2) }

    // good operand, transform executes
    let d2 = d1.flatMap { Deferred<Double, TestError>(error: TestError($0)).delay(seconds: 0.01) }

    // bad operand, transform short-circuited
    let d3 = d2.flatMap { _ -> Deferred<Int, TestError> in fatalError(#function) }
    d3.beginExecution()

    XCTAssertEqual(d1.value, value*2)
    XCTAssertEqual(d1.error, nil)
    XCTAssertEqual(d2.value, nil)
    XCTAssertEqual(d2.error, TestError(value*2))
    XCTAssertEqual(d3.value, nil)
    XCTAssertEqual(d3.error, d2.error)
  }

  func testTryFlatMap()
  {
    let value = nzRandom()
    let d0 = Deferred<Int, Never>(value: value)

    // good operand, good transform
    let d1 = d0.tryFlatMap(qos: .utility, transform: { Deferred(value: $0*2) })

    // good operand, transform errors
    let d2 = d1.tryFlatMap { Deferred<Double, Error>(error: TestError($0)).delay(seconds: 0.01) }

    // bad operand, transform short-circuited
    let d3 = d2.tryFlatMap { _ -> Deferred<Int, Error> in fatalError(#function) }
    d3.beginExecution()

    XCTAssertEqual(d1.value, value*2)
    XCTAssertEqual(d1.error, nil)
    XCTAssertEqual(d2.value, nil)
    XCTAssertEqual(d2.error, TestError(value*2))
    XCTAssertEqual(d3.value, nil)
    XCTAssertEqual(d3.error, TestError(value*2))
  }

  func testFlatMapError()
  {
    let value = nzRandom()
    let d0 = Deferred<Int, TestError>(error: TestError(value))

    // bad operand, transform executes
    let d1 = d0.flatMapError(qos: .utility) { Deferred<Int, TestError>(error: TestError($0.error*2)) }

    // bad operand, transform returns value
    let d2 = d1.flatMapError { Deferred<Int, Cancellation>(value: $0.error).delay(seconds: 0.01) }

    // good operand, transform short-circuited
    let d3 = d2.flatMapError { _ -> Deferred<Int, NSError> in fatalError(#function) }

    // FIXME: un-comment this once on-demand execution is reinstated
    // XCTAssertEqual(d1.state, .waiting)
    // XCTAssertEqual(d2.state, .waiting)
    // XCTAssertEqual(d3.state, .waiting)
    XCTAssertEqual(d3.value, value*2)
    XCTAssertEqual(d2.state, .resolved)
    XCTAssertEqual(d1.state, .resolved)
    XCTAssertEqual(d3.error, nil)
    XCTAssertEqual(d2.value, d3.value)
    XCTAssertEqual(d2.error, nil)
    XCTAssertEqual(d1.value, nil)
    XCTAssertEqual(d1.error, TestError(value*2))
  }
  
  func testFlatten1()
  {
    let value = nzRandom()
    let error = nzRandom()

    let t1 = Deferred<Deferred<Int, Error>, Error>(error: TestError(error))
    let d1 = t1.flatten()
    XCTAssertEqual(d1.error, TestError(error))

    let t2 = Deferred<Deferred<Int, Error>, Error>(value: Deferred(value: value))
    let d2 = t2.flatten()
    XCTAssertEqual(d2.value, value)

    let t3 = Deferred<Deferred<Int, Error>, Error>(value: Deferred(value: value).delay(seconds: 0.01))
    let d3 = t3.flatten()
    t3.cancel()
    XCTAssertEqual(d3.value, value)

    let t4 = Deferred<Deferred<Int, Error>, Error>(value: Deferred(error: TestError(error))).delay(seconds: 0.01)
    let d4 = t4.flatten()
    t4.cancel(String(error))
    XCTAssertEqual(d4.error, Cancellation.canceled(String(error)))

    let t5 = Deferred<Deferred<Int, Error>, Error>(value: Deferred(value: value)).delay(seconds: 0.01)
    let d5 = t5.flatten()
    XCTAssertEqual(d5.value, value)

    let t6 = Deferred<Deferred<Int, Error>, Error>(value: Deferred(value: value).delay(seconds: 0.01))
    let d6 = t6.delay(seconds: 0.02).flatten()
    XCTAssertEqual(d6.value, value)

    // let wontCompile = Deferred(value: 99).flatten()
  }

  func testFlatten2()
  {
    let value = nzRandom()

    let d1 = Deferred(value: Deferred<Int, Error>(value: value)).flatten()
    // error type of the intermediate `Deferred` is inferred to be `Never`
    XCTAssertEqual(d1.value, value)

    let t2 = Deferred<Deferred<Int, Error>, Never>(value: Deferred(value: value).delay(seconds: 0.01))
    let d2 = t2.flatten()
    XCTAssertEqual(d2.value, value)

    let t3 = Deferred<Deferred<Int, Error>, Never>(value: Deferred(value: value)).delay(seconds: 0.01)
    let d3 = t3.flatten()
    XCTAssertEqual(d3.value, value)

    let t4 = Deferred<Deferred<Int, Error>, Never>(value: Deferred(value: value).delay(seconds: 0.01))
    let d4 = t4.delay(seconds: 0.02).flatten()
    XCTAssertEqual(d4.value, value)
  }

  func testEnqueuing()
  {
    let r1 = nzRandom()
    let r2 = nzRandom()

    let t1 = Deferred<Int, Never>(value: r1).enqueuing(at: .utility, serially: false)
    XCTAssertEqual(t1.value, r1)

    let t2 = Deferred<Int, Never>(value: r2).delay(seconds: 0.01).enqueuing(at: .userInitiated)
    XCTAssertEqual(t2.value, r2)
  }

  func testQoS()
  {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    let q = DispatchQueue.global(qos: .utility)
    let qb = Deferred(queue: q, task: { qos_class_self() }).enqueuing(at: .background, serially: false)
    // Verify that the block's QOS was adjusted and is different from the queue's
    XCTAssertEqual(qb.value, QOS_CLASS_UTILITY)
    XCTAssertEqual(qb.qos, DispatchQoS.background)

    let e1 = expectation(description: "e1")
    let q1 = Deferred<qos_class_t, Never>(qos: .background, value: qos_class_self())
    q1.onValue {
      qosv in
      // Verify that the QOS has been adjusted
      XCTAssertNotEqual(qosv, qos_class_self())
      XCTAssertEqual(qos_class_self(), QOS_CLASS_BACKGROUND)
      e1.fulfill()
    }

    let e2 = expectation(description: "e2")
    let q2 = qb.enqueuing(at: .background, serially: true)
    q2.notify { _ in e2.fulfill() }

    let e3 = expectation(description: "e3")
    let q3 = q2.map(qos: .userInitiated) {
      qosv -> qos_class_t in
      XCTAssertEqual(qosv, QOS_CLASS_UTILITY)
      // Verify that the QOS has changed
      XCTAssertNotEqual(qosv, qos_class_self())
      // This block is running at the requested QOS
      XCTAssertEqual(qos_class_self(), QOS_CLASS_USER_INITIATED)
      e3.fulfill()
      return qos_class_self()
    }

    let e4 = expectation(description: "e4")
    let q4 = q3.enqueuing(at: .userInteractive)
    q4.onValue {
      qosv in
      // Last block was in fact executing at QOS_CLASS_USER_INITIATED
      XCTAssertEqual(qosv, QOS_CLASS_USER_INITIATED)
      // Last block wasn't executing at the queue's QOS
      XCTAssertNotEqual(qosv, QOS_CLASS_BACKGROUND)
      // This block is executing at the queue's QOS.
      XCTAssertEqual(qos_class_self(), QOS_CLASS_USER_INTERACTIVE)
      XCTAssertNotEqual(qos_class_self(), QOS_CLASS_BACKGROUND)
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

    let value1 = nzRandom()
    let value2 = nzRandom()
    let v1 = Deferred<Int, Error>(value: value1)
    let t1 = Deferred<(Int) -> Int, Never>(value: curriedSum(value2))
    let d1 = v1.apply(transform: t1)
    XCTAssertEqual(d1.value, value1+value2)

    // tuples must be explicitly destructured for multiple-argument transforms
    let v2 = Deferred<(Float, Float), Never>(value: (3.0, 4.1))
    let t2 = Deferred<((Float, Float)) -> Float, Never>(value: { (ft: (Float, Float)) in powf(ft.0, ft.1) })
    let d2 = v2.apply(transform: t2.delay(seconds: 0.01))
    XCTAssertEqual(d2.value, powf(3.0, 4.1))

    // error from operand is passed along to transformed result
    let v3 = Deferred<Int, TestError>(error: TestError(value2))
    let t3 = t1.delay(seconds: 0.01)
    let d3 = v3.apply(qos: .background, transform: t3)
    XCTAssertEqual(d3.value, nil)
    XCTAssertEqual(d3.error, TestError(value2))
  }

  func testCancelMap()
  {
    let d0 = Deferred<Int, Cancellation> { _ in }

    let e1 = expectation(description: #function)
    let d1 = d0.map { XCTFail(String($0)) }
    d1.onError { _ in e1.fulfill() }
    d1.cancel()
    XCTAssertEqual(d1.error, .canceled(""))

    let e2 = expectation(description: #function)
    let d2 = d0.tryMap { XCTFail(String($0)) }
    d2.onError { _ in e2.fulfill() }
    d2.cancel()
    XCTAssertEqual(d2.error, Cancellation.canceled(""))

    let e3 = expectation(description: #function)
    let d3 = d0.mapError { _ in TestError(0) as Error }
    d3.onError { _ in e3.fulfill() }
    d3.cancel()
    XCTAssertEqual(d3.error, Cancellation.canceled(""))

    d0.cancel("other")
    waitForExpectations(timeout: 1.0)
  }

  func testCancelFlatMap()
  {
    let d0 = Deferred<Int, Cancellation> { _ in }

    let e1 = expectation(description: #function)
    let d1 = d0.flatMap { Deferred(value: XCTFail(String($0))) }
    d1.onError { _ in e1.fulfill() }
    d1.cancel()
    XCTAssertEqual(d1.error, .canceled(""))

    let e2 = expectation(description: #function)
    let d2 = d0.tryFlatMap { Deferred(value: XCTFail(String($0))) }
    d2.onError { _ in e2.fulfill() }
    d2.cancel()
    XCTAssertEqual(d2.error, Cancellation.canceled(""))

    let e3 = expectation(description: #function)
    let d3 = d0.flatMapError { _ in Deferred(error: TestError(0) as Error) }
    d3.onError { _ in e3.fulfill() }
    d3.cancel()
    XCTAssertEqual(d3.error, Cancellation.canceled(""))

    d0.cancel("other")
    waitForExpectations(timeout: 1.0)
  }

  func testCancelRecover()
  {
    let d0 = Deferred<Int, Error> { _ in }

    let e1 = expectation(description: #function)
    let d1 = d0.recover { _ in Deferred(error: TestError(0) as Error) }
    d1.onError { _ in e1.fulfill() }
    d1.cancel()
    XCTAssertEqual(d1.error, Cancellation.canceled(""))

    d0.cancel("other")
    waitForExpectations(timeout: 1.0)
  }

  func testCancelApply()
  {
    let d0 = Deferred<Int, Error> { _ in }
    let t0 = Deferred<(Int) -> Int, Never> { 2*$0 }

    let e1 = expectation(description: #function)
    let d1 = d0.apply(transform: t0)
    d1.onError { _ in e1.fulfill() }
    d1.cancel()
    XCTAssertEqual(d1.error, Cancellation.canceled(""))

    // TODO: find a way to exercise the inner early return in `apply`

    d0.cancel("other")
    waitForExpectations(timeout: 1.0)
  }

  func testValidate1()
  {
    let d = (0..<10).map({ Deferred<Int, Never>.init(value:$0) })
    let m = String(nzRandom())

    let v = d.map({ $0.validate(qos: .background, predicate: { $0%2 == 0 }, message: m) })
    let e = v.compactMap { $0.error }
    XCTAssertEqual(e.count, d.count/2)
    XCTAssertEqual(e.first, Invalidation.invalid(m))
  }

  func testValidate2()
  {
    let d = (0..<10).map({Deferred<Int, Never>.init(value:$0)})

    let v = d.map({ $0.validate(qos: .utility, predicate: { if $0%2 == 0 { throw TestError($0) } }) })
    let e = v.compactMap { $0.error }
    XCTAssertEqual(e.count, d.count/2)
    XCTAssertEqual(e.last, TestError(8))
  }

  func testOptional() throws
  {
    let rnd = nzRandom()

    var opt = rnd as Optional
    let d1 = opt.deferred()
    XCTAssertEqual(d1.value, rnd)
    XCTAssertEqual(d1.error, nil)

    opt = nil
    let d2 = opt.deferred()
    XCTAssertEqual(d2.value, nil)
    XCTAssertNotNil(d2.error)
  }

  func testSplit()
  {
    let r2v = nzRandom()
    let d2v = Deferred<(Int, String), Never>(value: (r2v, String(r2v)))
    let s2v = d2v.split()
    XCTAssertEqual(s2v.0.value, s2v.1.value.flatMap(Int.init))

    let d2e = Deferred<(Int, String), TestError>(error: TestError(nzRandom()))
    let s2e = d2e.split()
    XCTAssertEqual(s2e.0.error, s2e.1.error)

    let r3 = nzRandom()
    let d3 = Deferred<(Int, Double, String), Never>(value: (r3, Double(r3), String(r3)))
    let s3 = d3.split()
    XCTAssertEqual(s3.0.value.map(Double.init), s3.1.value)
    XCTAssertEqual(s3.0.value.map(String.init), s3.2.value)

    let r4 = nzRandom()
    let d4 = Deferred<(Int, UInt, Double, String), Never>(value: (r4, r4.magnitude, Double(r4), String(r4)))
    let s4 = d4.split()
    XCTAssertEqual(s4.0.value.map({ $0.magnitude }), s4.1.value)
    XCTAssertEqual(s4.1.value.map(Double.init), s4.2.value.map({ $0.magnitude }))
    XCTAssertEqual(s4.0.value.map(String.init), s4.3.value)
  }

  func  testExecute()
  {
    let deferred = Deferred<Void, Never> { _ in }
    // FIXME: un-comment this once on-demand execution is reinstated
    // XCTAssertEqual(deferred.state, .waiting)
    let executed = deferred.execute
    XCTAssertEqual(executed.state, .executing)
    XCTAssertEqual(ObjectIdentifier(executed), ObjectIdentifier(deferred))
  }
}
