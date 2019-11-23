//
//  DeferredCombinationTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 30/01/2017.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch

import deferred

class DeferredCombinationTests: XCTestCase
{
  func testReduce()
  {
    let count = 10
    let inputs = (0..<count).map {
      i -> Deferred<Int, Never> in
      return Deferred<Int, Never>(value: i).map {
        i -> Int in
        // print(i)
        return 2*i
      }
    }

    let c = reduce(inputs, initial: 0, combine: { $0 + $1 })

    XCTAssertEqual(c.value, 90)
    XCTAssertEqual(c.error, nil)
  }

  func testReduceCancel()
  {
    let count = 10
    let inputs = (0..<count).map {
      i in
      return Deferred<Int, Cancellation> {
        resolver in
        // print(i)
        resolver.resolve(value: i)
      }
    }

    let cancel = Int(nzRandom() % numericCast(count))
    inputs[cancel].cancel(String(cancel))
    let c = reduce(inputs, initial: 0, combine: { $0 + $1 })

    XCTAssertEqual(c.value, nil)
    XCTAssertEqual(c.error, .canceled(String(cancel)))
  }

  func testCombine()
  {
    let count = 10
    let inputs = (0..<count).map {
      i -> Deferred<Int, Never> in
      return Deferred<Int, Never>(value: i).map {
        i -> Int in
        // print(i)
        return 2*i
      }
    }

    let c = combine(inputs).map(transform: { $0.reduce(0, { $0 + $1 }) })

    XCTAssertEqual(c.value, 90)
    XCTAssertEqual(c.error, nil)
  }

  func testCombineCancel()
  {
    let count = 10
    let inputs = (1...count).map {
      i in
      return Deferred<Int, Cancellation> {
        resolver in
        // print(i)
        resolver.resolve(value: i)
      }
    }

    let cancel = Int(nzRandom() % numericCast(count))
    inputs[cancel].cancel(String(cancel))
    let c = combine(inputs)

    XCTAssertEqual(c.value, nil)
    XCTAssertEqual(c.error, .canceled(String(cancel)))
  }

  func testCombine2()
  {
    let v1 = Int(nzRandom())
    let v2 = UInt64(nzRandom())

    let d1 = Deferred<Int, Never> { $0.resolve(value: v1) }
    let d2 = Deferred<UInt64, Never> { $0.resolve(value: v2) }
    let d3 = d1.delay(.microseconds(10))
    let d4 = d2.delay(.milliseconds(10))

    let c = combine(d3, d4.timeout(.microseconds(10)))
    XCTAssertEqual(c.value?.0, nil)
    XCTAssertEqual(c.value?.1, nil)
    XCTAssertEqual(c.error, Cancellation.timedOut(""))

    let d = combine(d3, d4)
    XCTAssertEqual(d.value?.0, v1)
    XCTAssertEqual(d.value?.1, v2)
  }

  func testCombine3()
  {
    let v1 = Int(nzRandom())
    let v2 = UInt64(nzRandom())
    let v3 = String(nzRandom())

    let d1 = Deferred<Int, TestError> { $0.resolve(value: v1) }
    let d2 = Deferred<UInt64, Never>  { $0.resolve(value: v2) }
    let d3 = Deferred<String, NSError>{ $0.resolve(value: v3) }

    let c = combine(d1,d2,d3.delay(seconds: 0.001)).value
    XCTAssert(c?.0 == v1)
    XCTAssert(c?.1 == v2)
    XCTAssert(c?.2 == v3)
  }

  func testCombine4()
  {
    let v1 = Int(nzRandom())
    let v2 = UInt64(nzRandom())
    let v3 = String(nzRandom())
    let v4 = sin(Double(v2))

    let d1 = Deferred<Int, TestError> { $0.resolve(value: v1) }
    let d2 = Deferred<UInt64, Never>  { $0.resolve(value: v2) }
    let d3 = Deferred<String, NSError>{ $0.resolve(value: v3) }
    let d4 = Deferred<Double, CFError>{ $0.resolve(value: v4) }

    let c = combine(d1,d2,d3,d4).value
    XCTAssert(c?.0 == v1)
    XCTAssert(c?.1 == v2)
    XCTAssert(c?.2 == v3)
    XCTAssert(c?.3 == v4)
  }
}

class DeferredCombinationTimedTests: XCTestCase
{
  let loopTestCount = 2_000

  func testPerformanceReduce()
  {
    let iterations = loopTestCount

    measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
      let inputs = (1...iterations).map { Deferred<Int, Never>(value: $0) }
      self.startMeasuring()
      let c = reduce(inputs, initial: 0, combine: +)
      let v = try? c.get()
      XCTAssert(v == (iterations*(iterations+1)/2))
      self.stopMeasuring()
    }
  }

  func testPerformanceABAProneReduce()
  {
    let iterations = loopTestCount / 10

    measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
      let inputs = (1...iterations).map {Deferred<Int, Never>(value: $0) }
      self.startMeasuring()
      let accumulator = Deferred<Int, Never>(value: 0)
      let c = inputs.reduce(accumulator) {
        (accumulator, deferred) in
        accumulator.flatMap {
          u in deferred.map { t in u+t }
        }
      }
      let v = try? c.get()
      XCTAssert(v == (iterations*(iterations+1)/2))
      self.stopMeasuring()
    }
  }

  func testPerformanceCombine()
  {
    let iterations = loopTestCount

    measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
      let inputs = (1...iterations).map { Deferred<Int, Never>(value: $0) }
      self.startMeasuring()
      let c = combine(inputs)
      let v = try? c.get()
      XCTAssert(v?.count == iterations)
      self.stopMeasuring()
    }
  }

}
