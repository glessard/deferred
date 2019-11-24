//
//  DeferredSelectionTests.swift
//  deferredTests
//
//  Created by Guillaume Lessard on 5/2/19.
//  Copyright © 2019 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch

import deferred

extension Deferred
{
  convenience init() { self.init(resolve: { _ in }) }
}

class DeferredSelectionTests: XCTestCase
{
  func testFirstValue() throws
  {
    func resolution(_ c: Int) -> ([Resolver<Int, Error>], Deferred<Int, Error>?)
    {
      var r = [Resolver<Int, Error>]()
      var d = [Deferred<Int, Error>]()
      for i in 0...c
      {
        let tbd = DeallocWitness(self.expectation(description: String(i)), task: { r.append($0) }).execute
        d.append(tbd.validate(predicate: {$0 == i}).execute)
      }
      XCTAssertEqual(r.count, d.count)
      return (r, firstValue(d, qos: .utility))
    }

    let count = 10
    let (resolvers, first) = resolution(count)

    let lucky = Int.random(in: 1..<count)
    XCTAssert(resolvers[count].resolve(error: TestError(count)))
    XCTAssert(resolvers[lucky].resolve(value: lucky))
    waitForExpectations(timeout: 1.0)

    XCTAssertEqual(first?.value, lucky)
    for r in resolvers { XCTAssertFalse(r.needsResolution) }
  }

  func testFirstValueEmptyCollection() throws
  {
    let zero = firstValue(Array<Deferred<Void, Never>>(), queue: DispatchQueue.global())
    XCTAssertNil(zero)
  }

  func testFirstValueError() throws
  {
    func noValue(_ c: Int) -> Deferred<Int, TestError>
    {
      let deferreds = (0..<c).map {
        i -> Deferred<Int, TestError> in
        let e = expectation(description: String(i))
        return DeallocWitness(e, task: { $0.resolve(error: TestError(i)) })
      }

      return firstValue(deferreds, cancelOthers: true)!
    }

    let count = 10
    let first = noValue(count)
    XCTAssertEqual(first.error, TestError(count-1))

    waitForExpectations(timeout: 1.0)
  }

  func testFirstResolved1() throws
  {
    func resolution(_ c: Int) -> ([Resolver<Int, Error>], Deferred<Int, Error>)
    {
      var r: [Resolver<Int, Error>] = []
      var d: [Deferred<Int, Error>] = []
      for i in 0...c
      {
        let tbd = DeallocWitness(self.expectation(description: String(i)), task: { r.append($0) }).execute
        d.append(tbd)
      }
      return (r, firstResolved(d, qos: .utility, cancelOthers: false).value!)
    }

    let count = 10
    let (r, f) = resolution(count)

    let e = Int.random(in: 1..<count)
    r[e].resolve(value: e)

    waitForExpectations(timeout: 1.0)

    XCTAssertEqual(try f.get(), e)
  }

  func testFirstResolved2() throws
  {
    func resolution(_ c: Int) -> ([Resolver<Int, Error>], Deferred<Int, Error>)
    {
      var r: [Resolver<Int, Error>] = []
      var d: [Deferred<Int, Error>] = []
      for i in 0...c
      {
        let tbd = DeallocWitness(self.expectation(description: String(i)), task: { r.append($0) }).validate(predicate: {$0 == i})
        let e = expectation(description: "Resolution \(i)")
        tbd.notify  {
          result in
          if result.value == i { e.fulfill() }
          else if result.error != nil
          {
            XCTAssertEqual(result.error, Cancellation.notSelected)
            e.fulfill()
          }
        }
        d.append(tbd)
      }
      return (r, firstResolved(d, qos: .utility, cancelOthers: true).value!)
    }

    let count = 10
    let (r, f) = resolution(count)

    let e = Int.random(in: 1..<count)
    r[e].resolve(value: e)

    waitForExpectations(timeout: 1.0)

    XCTAssertEqual(try f.get(), e)
  }

  func testSelectFirstResolvedBinary1()
  {
    let e1 = expectation(description: #function + "1")
    let e2 = expectation(description: #function + "2")
    let r2 = nzRandom()
    var t2: Resolver<Int, Error>! = nil

    let (s1, s2) = firstResolved(DeallocWitness<Double, Never>(e1),
                                 DeallocWitness<Int, Error>(e2) { t2 = $0 },
                                 canceling: true)
    s1.notify { XCTAssertEqual($0.error, Cancellation.notSelected) }
    s2.notify { XCTAssertEqual($0.value, r2) }

    t2.resolve(value: r2)

    waitForExpectations(timeout: 1.0)
  }

  func testSelectFirstResolvedBinary2()
  {
    let r1 = Double(nzRandom())
    let e2 = expectation(description: #function)
    var r2: Resolver<Int, Error>! = nil

    let (s1, s2) = firstResolved(Deferred<Double, Never>(qos: .utility, value: r1),
                                 DeallocWitness(e2) { r2 = $0 })
    s1.notify { XCTAssertEqual($0.value, r1) }
    s2.notify { XCTAssertEqual($0.error, Cancellation.notSelected) }

    waitForExpectations(timeout: 1.0)
    XCTAssertEqual(r2.needsResolution, false)
  }

  func testSelectFirstResolvedTernary()
  {
    let r1 = nzRandom()
    let d2 = Deferred<Float, Never>()

    let (s1, s2, s3) = firstResolved(Deferred<Int, TestError>(error: TestError(r1)),
                                     d2,
                                     Deferred<Double, NSError>(),
                                     canceling: true)

    XCTAssertEqual(s1.error, TestError(r1))
    XCTAssertEqual(d2.error, Cancellation.notSelected)
    XCTAssertEqual(s2.error, Cancellation.notSelected)
    XCTAssertEqual(s3.error, Cancellation.notSelected)
  }

  func testSelectFirstResolvedQuaternary()
  {
    let r1 = nzRandom()
    let d2 = Deferred<String, Never>()

    let (s1, s2, s3, s4) = firstResolved(Deferred<Int, TestError>(error: TestError(r1)),
                                         d2,
                                         Deferred<Double, NSError>(),
                                         Deferred<Void, Error>(),
                                         canceling: true)

    XCTAssertEqual(s1.error, TestError(r1))
    XCTAssertEqual(d2.error, Cancellation.notSelected)
    XCTAssertEqual(s2.error, Cancellation.notSelected)
    XCTAssertEqual(s3.error, Cancellation.notSelected)
    XCTAssertEqual(s4.error, Cancellation.notSelected)
  }

  func testSelectFirstValueBinary1()
  {
    let d1 = Deferred<Double, Cancellation>()
    let e2 = expectation(description: #function)
    var r2: Resolver<Int, Never>!

    let (s1, s2) = firstValue(d1, DeallocWitness(e2, task: { r2 = $0 }), canceling: true)
    s1.notify { XCTAssertEqual($0.error, Cancellation.notSelected) }
    s2.notify { XCTAssertNotNil($0.value) }

    r2.resolve(value: nzRandom())

    waitForExpectations(timeout: 1.0)
    XCTAssertEqual(d1.error, Cancellation.notSelected)
  }

  func testSelectFirstValueBinary2()
  {
    let r1 = Double(nzRandom())
    let e2 = expectation(description: #function)

    let (s1, s2) = firstValue(Deferred<Double, NSError>(value: r1), DeallocWitness<Int, Never>(e2))
    s1.onValue { XCTAssertEqual($0, r1) }
    s2.notify { XCTAssertEqual($0.error, Cancellation.notSelected) }

    waitForExpectations(timeout: 1.0)
  }

  func testSelectFirstValueBinary3()
  {
    let r1 = nzRandom()
    let r2 = nzRandom()
    let e2 = expectation(description: #function)

    let (s1, s2) = firstValue(Deferred<Int, TestError>(error: TestError(r1)),
                              DeallocWitness<Void, Error>(e2, task: { $0.resolve(error: TestError(r2)) }))
    s1.notify { XCTAssertEqual($0.error, TestError(r1)) }
    s2.notify { XCTAssertEqual($0.error, TestError(r2)) }

    waitForExpectations(timeout: 1.0)
  }

  func testSelectFirstValueTernary1()
  {
    let r1 = nzRandom()
    let t3 = Deferred<Double, Error>()

    let (s1, s2, s3) = firstValue(Deferred<Int, Never>(value: r1),
                                  Deferred<Int, TestError>(error: TestError()),
                                  t3,
                                  canceling: true)

    XCTAssertEqual(s1.value, r1)
    XCTAssertEqual(s2.error, Cancellation.notSelected)
    XCTAssertEqual(t3.error, Cancellation.notSelected)
    XCTAssertEqual(s3.error, Cancellation.notSelected)
  }

  func testSelectFirstValueTernary2()
  {
    let r1 = nzRandom()
    let r2 = nzRandom()
    let r3 = nzRandom()

    let (s1, s2, s3) = firstValue(Deferred<Float, TestError>(error: TestError(r1)),
                                  Deferred<Void, TestError>(error: TestError(r2)),
                                  Deferred<Double, Error>(error: TestError(r3)))

    XCTAssertEqual(s1.error, TestError(r1))
    XCTAssertEqual(s2.error, TestError(r2))
    XCTAssertEqual(s3.error, TestError(r3))
  }

  func testSelectFirstValueQuaternary1()
  {
    let r = nzRandom()
    let t3 = Deferred<Double, Cancellation>()

    let (s1, s2, s3, s4) = firstValue(Deferred<Void, TestError>(error: TestError(r)),
                                      Deferred<Int, Never>(value: r),
                                      t3,
                                      Deferred<Int, Error>(),
                                      canceling: true)

    XCTAssertEqual(s1.error, Cancellation.notSelected)
    XCTAssertEqual(s2.value, r)
    XCTAssertEqual(t3.error, Cancellation.notSelected)
    XCTAssertEqual(s3.error, Cancellation.notSelected)
    XCTAssertEqual(s4.error, Cancellation.notSelected)
  }

  func testSelectFirstValueQuaternary2()
  {
    let r1 = nzRandom()
    let r2 = nzRandom()
    let r3 = nzRandom()
    let r4 = nzRandom()

    let (s1, s2, s3, s4) = firstValue(Deferred<Float, TestError>(error: TestError(r1)),
                                      Deferred<Void, Error>(error: TestError(r2)),
                                      Deferred<Int, TestError>(error: TestError(r3)),
                                      Deferred<Double, Error>(error: TestError(r4)))

    XCTAssertEqual(s1.error, TestError(r1))
    XCTAssertEqual(s2.error, TestError(r2))
    XCTAssertEqual(s3.error, TestError(r3))
    XCTAssertEqual(s4.error, TestError(r4))
  }
}
