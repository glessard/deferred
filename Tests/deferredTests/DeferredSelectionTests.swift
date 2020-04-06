//
//  DeferredSelectionTests.swift
//  deferredTests
//
//  Created by Guillaume Lessard on 2019-05-02.
//  Copyright © 2019-2020 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch

import deferred

extension Deferred
{
  convenience init() { self.init(task: { _ in }) }
}

class DeferredSelectionTests: XCTestCase
{
  func testFirstValueCollection() throws
  {
    func resolution(_ c: Int) -> ([Resolver<Int, Error>], Deferred<Int, Error>?)
    {
      let q = DispatchQueue(label: #function)
      var r = [Resolver<Int, Error>]()
      var d = [Deferred<Int, Error>]()
      for i in 0...c
      {
        let tbd = DeallocWitness(self.expectation(description: String(i)), queue: q) { r.append($0) }
        d.append(tbd)
      }
      for deferred in d { deferred.beginExecution() }
      q.sync { XCTAssertEqual(r.count, d.count) }
      return (r, firstValue(d, qos: .utility))
    }

    let count = 10
    let (resolvers, first) = resolution(count)

    let lucky = Int.random(in: 1..<count)
    resolvers[count].resolve(error: TestError(count))
    resolvers[lucky].resolve(value: lucky)
    first?.beginExecution()

    waitForExpectations(timeout: 1.0)

    XCTAssertEqual(first?.value, lucky)
    for r in resolvers { XCTAssertFalse(r.needsResolution) }
  }

  func testFirstValueSequence() throws
  {
    func resolution(_ c: Int) -> ([Resolver<Int, Error>], Deferred<Int, Error>?)
    {
      let q = DispatchQueue(label: #function)
      var r = [Resolver<Int, Error>]()
      var d = [Deferred<Int, Error>]()
      for i in 0...c
      {
        let tbd = DeallocWitness(self.expectation(description: String(i)), queue: q) { r.append($0) }
        d.append(tbd)
      }
      for deferred in d { deferred.beginExecution() }
      q.sync { XCTAssertEqual(r.count, d.count) }
      return (r, firstValue(AnySequence(d), qos: .utility))
    }

    let count = 10
    let (resolvers, first) = resolution(count)

    let lucky = Int.random(in: 1..<count)
    resolvers[count].resolve(error: TestError(count))
    resolvers[lucky].resolve(value: lucky)
    first?.beginExecution()

    waitForExpectations(timeout: 1.0)

    XCTAssertEqual(first?.value, lucky)
    for r in resolvers { XCTAssertFalse(r.needsResolution) }
  }

  func testFirstValueEmptyCollection() throws
  {
    let empty: [Deferred<Void, Never>] = []
    let zero = firstValue(empty, queue: DispatchQueue.global())
    XCTAssertNil(zero)
  }

  func testFirstValueEmptySequence() throws
  {
    let empty: [Deferred<Void, Never>] = []
    let zero = firstValue(AnySequence(empty), queue: DispatchQueue.global())
    XCTAssertNil(zero)
  }

  func testFirstValueCollectionError() throws
  {
    func noValue(_ c: Int) -> Deferred<Int, Error>
    {
      let deferreds = (0..<c).map {
        i -> Deferred<Int, Error> in
        let e = expectation(description: String(i))
        return DeallocWitness(e, task: { $0.resolve(error: TestError(i)) })
      }

      return firstValue(deferreds, cancelOthers: true)!
    }

    let count = 10
    let first = noValue(count)
    first.onError { XCTAssertEqual($0, TestError(count-1)) }

    waitForExpectations(timeout: 1.0)
    withExtendedLifetime(first) {}
  }

  func testFirstValueSequenceError() throws
  {
    func noValue(_ c: Int) -> Deferred<Int, Error>
    {
      let deferreds = (0..<c).map {
        i -> Deferred<Int, Error> in
        let e = expectation(description: String(i))
        return DeallocWitness(e, task: { $0.resolve(error: TestError(i)) })
      }

      return firstValue(AnySequence(deferreds), cancelOthers: true)!
    }

    let count = 10
    let first = noValue(count)
    first.onError { XCTAssertEqual($0, TestError(count-1)) }

    waitForExpectations(timeout: 1.0)
    withExtendedLifetime(first) {}
  }

  func testFirstResolvedCollection() throws
  {
    let count = 10
    let e = Int.random(in: 1..<count)

    func resolution() -> ([Resolver<Int, Error>], Deferred<Int, Error>)
    {
      let q = DispatchQueue(label: #function)
      var r: [Resolver<Int, Error>] = []
      var d: [Deferred<Int, Error>] = []
      for i in 0...count
      {
        let tbd = DeallocWitness(self.expectation(description: String(i)), queue: q, task: { r.append($0) })
        if i == e
        { tbd.beginExecution() }
        else
        { tbd.notify { XCTAssertEqual($0, Cancellation.notSelected) } }
        d.append(tbd)
      }
      q.sync { XCTAssertEqual(r.count, d.count) }
      return (r, firstResolved(d, qos: .utility, cancelOthers: true)!)
    }

    let (r, f) = resolution()
    for resolver in r { XCTAssertEqual(resolver.needsResolution, true) }
    r[e].resolve(error: TestError(e))

    XCTAssertEqual(f.error, TestError(e))

    waitForExpectations(timeout: 1.0)
  }

  func testFirstResolvedSequence() throws
  {
    let count = 10
    let e = Int.random(in: 1..<count)

    func resolution() -> ([Resolver<Int, Error>], Deferred<Int, Error>)
    {
      let q = DispatchQueue(label: #function)
      var r: [Resolver<Int, Error>] = []
      var d: [Deferred<Int, Error>] = []
      for i in 0...count
      {
        let tbd = DeallocWitness(self.expectation(description: String(i)), queue: q, task: { r.append($0) })
        if i == e
        { tbd.beginExecution() }
        else
        { tbd.notify { XCTAssertEqual($0, Cancellation.notSelected) } }
        d.append(tbd)
      }
      q.sync { XCTAssertEqual(r.count, d.count) }
      return (r, firstResolved(AnySequence(d), qos: .utility, cancelOthers: true)!)
    }

    let (r, f) = resolution()
    for resolver in r { XCTAssertEqual(resolver.needsResolution, true) }
    r[e].resolve(value: e)
    XCTAssertEqual(try f.get(), e)

    waitForExpectations(timeout: 1.0)
  }

  func testFirstResolvedEmptyCollection() throws
  {
    let zero = firstResolved(Array<Deferred<Void, Never>>(), queue: DispatchQueue.global())
    XCTAssertNil(zero)
  }

  func testFirstResolvedEmptySequence() throws
  {
    let zero = firstResolved(AnySequence(EmptyCollection<Deferred<Void, Never>>()))
    XCTAssertNil(zero)
  }

  func testSelectFirstResolvedBinary()
  {
    let e1 = expectation(description: #function + "1")
    let e2 = expectation(description: #function + "2")
    let r2 = nzRandom()
    let q2 = DispatchQueue(label: #function)
    var t2: Resolver<Int, Error>! = nil

    let (s1, s2) = firstResolved(DeallocWitness<Double, Cancellation>(e1),
                                 DeallocWitness<Int, Error>(e2, queue: q2, task: { t2 = $0 }).execute,
                                 cancelOthers: true)
    q2.sync { XCTAssertNotNil(r2) }
    s1.notify { XCTAssertEqual($0, Cancellation.notSelected) }
    s2.notify { XCTAssertEqual($0, r2) }

    t2.resolve(value: r2)

    waitForExpectations(timeout: 1.0)
  }

  func testSelectFirstResolvedTernary()
  {
    let r1 = nzRandom()
    let d2 = Deferred<Float, Error>()

    let (s1, s2, s3) = firstResolved(Deferred<Int, TestError>(error: TestError(r1)),
                                     d2,
                                     Deferred<Double, NSError>(),
                                     cancelOthers: true)

    XCTAssertEqual(s1.error, TestError(r1))
    XCTAssertEqual(d2.error, Cancellation.notSelected)
    XCTAssertEqual(s2.error, Cancellation.notSelected)
    XCTAssertEqual(s3.error, Cancellation.notSelected)
  }

  func testSelectFirstResolvedQuaternary()
  {
    let r1 = nzRandom()
    let d2 = Deferred<String, Error>()

    let (s1, s2, s3, s4) = firstResolved(Deferred<Int, TestError>(error: TestError(r1)),
                                         d2,
                                         Deferred<Double, NSError>(),
                                         Deferred<Void, Cancellation>(),
                                         cancelOthers: true)

    XCTAssertEqual(s1.error, TestError(r1))
    XCTAssertEqual(d2.error, Cancellation.notSelected)
    XCTAssertEqual(s2.error, Cancellation.notSelected)
    XCTAssertEqual(s3.error, Cancellation.notSelected)
    XCTAssertEqual(s4.error, Cancellation.notSelected)
  }

  func testSelectFirstValueBinary1()
  {
    let d1 = Deferred<Double, Cancellation>()
    let (r2, d2) = Deferred<Int, Never>.CreatePair()

    let (s1, s2) = firstValue(d1, d2, cancelOthers: true)
    XCTAssertEqual(d1.state, .waiting)
    XCTAssertEqual(d2.state, .waiting)
    XCTAssertEqual(s1.state, .waiting)
    XCTAssertEqual(s2.state, .waiting)

    let e2 = expectation(description: #function)
    s2.notify { _ in e2.fulfill() }
    r2.resolve(value: nzRandom())

    waitForExpectations(timeout: 1.0) { _ in d1.cancel() }
    XCTAssertEqual(s2.value, d2.value)
    XCTAssertEqual(s1.error, Cancellation.notSelected)
    XCTAssertEqual(d1.error, Cancellation.notSelected)
  }

  func testSelectFirstValueBinary2()
  {
    let r1 = nzRandom()
    let r2 = nzRandom()
    let e2 = expectation(description: #function)

    let (s1, s2) = firstValue(Deferred<Int, TestError>(error: TestError(r1)),
                              DeallocWitness<Void, Error>(e2, task: { $0.resolve(error: TestError(r2)) }))
    s1.notify { XCTAssertEqual($0, TestError(r1)) }
    s2.notify { XCTAssertEqual($0, TestError(r2)) }

    waitForExpectations(timeout: 1.0)
  }

  func testSelectFirstValueMemoryRelease()
  {
    do {
      let (s1, s2) = firstValue(DeallocWitness<Void, Error>(expectation(description: #function + "1")),
                                DeallocWitness<Void, Error>(expectation(description: #function + "2")))
      s1.beginExecution()
      s2.beginExecution()
    }

    waitForExpectations(timeout: 1.0)
  }

  func testSelectFirstValueRetainMemory()
  {
    let d1 = Deferred<Void, Never>() { _ in }
    let e2 = expectation(description: #function)

    let (s1, s2) = firstValue(d1, Deferred<Void, Error> { _ in e2.fulfill() } )

    let q = DispatchQueue(label: #function)
    q.asyncAfter(deadline: .now() + 0.01) { s1.beginExecution() }

    XCTAssertEqual(s1.state, .waiting)
    XCTAssertEqual(s2.state, .waiting)
    XCTAssertEqual(d1.state, .waiting)
    waitForExpectations(timeout: 1.0)
    XCTAssertEqual(d1.state, .executing)
  }

  func testSelectFirstValueTernary1()
  {
    let r1 = nzRandom()
    let t3 = Deferred<Double, Error>()

    let (s1, s2, s3) = firstValue(Deferred<Int, Never>(value: r1),
                                  Deferred<Int, TestError>(error: TestError()),
                                  t3,
                                  cancelOthers: true)

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
                                      cancelOthers: true)

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
