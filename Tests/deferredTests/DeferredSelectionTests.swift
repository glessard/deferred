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

private class DeallocTBD: TBD<Int>
{
  let e: XCTestExpectation
  init(_ expectation: XCTestExpectation, task: (Resolver<Int>) -> Void = { _ in })
  {
    e = expectation
    super.init(task: task)
  }
  deinit {
    e.fulfill()
  }
}

class DeferredSelectionTests: XCTestCase
{
  func testFirstValueCollection() throws
  {
    func resolution(_ c: Int) -> ([Resolver<Int>], Deferred<Int>)
    {
      var r = [Resolver<Int>]()
      var d = [Deferred<Int>]()
      for i in 0...c
      {
        let tbd = DeallocTBD(self.expectation(description: String(i)), task: { r.append($0) })
        d.append(tbd.validate(predicate: {$0 == i}))
      }
      return (r, firstValue(d, qos: .utility).timeout(seconds: 0.2))
    }

    let count = 10
    let (resolvers, first) = resolution(count)

    let lucky = Int.random(in: 1..<count)
    XCTAssert(resolvers[count].resolve(error: TestError(count)))
    XCTAssert(resolvers[lucky].resolve(value: lucky))
    waitForExpectations(timeout: 0.1)

    XCTAssertEqual(first.value, lucky)
    for r in resolvers { XCTAssertFalse(r.needsResolution) }
  }

  func testFirstValueEmptyCollection() throws
  {
    let zero = firstValue(Array<Deferred<Void>>(), queue: DispatchQueue.global())
    do {
      _ = try zero.result.get()
      XCTFail()
    }
    catch DeferredError.invalid(let m) {
      XCTAssert(m != "")
    }
  }

  func testFirstValueCollectionError() throws
  {
    func noValue(_ c: Int) -> Deferred<Int>
    {
      let deferreds = (0..<c).map {
        i -> Deferred<Int> in
        let e = expectation(description: String(i))
        return DeallocTBD(e, task: { $0.resolve(error: TestError(i)) })
      }

      return firstValue(deferreds, cancelOthers: true)
    }

    let count = 10
    let first = noValue(count)
    XCTAssertEqual(first.error, TestError(count-1))

    waitForExpectations(timeout: 0.1)
  }

  func testFirstValueSequence() throws
  {
    func resolution(_ c: Int) -> ([Resolver<Int>], Deferred<Int>)
    {
      var r = [Resolver<Int>]()
      var d = [Deferred<Int>]()
      for i in 0...c
      {
        let tbd = DeallocTBD(self.expectation(description: String(i)), task: { r.append($0) })
        d.append(tbd.validate(predicate: {$0 == i}))
      }
      return (r, firstValue(d.makeIterator(), cancelOthers: true).timeout(seconds: 0.2))
    }

    let count = 10
    let (resolvers, first) = resolution(count)

    let lucky = Int.random(in: 1..<count)
    XCTAssert(resolvers[count].resolve(error: TestError(count)))
    XCTAssert(resolvers[lucky].resolve(value: lucky))
    waitForExpectations(timeout: 0.1)

    XCTAssertEqual(first.value, lucky)
  }

  func testFirstValueEmptySequence() throws
  {
    let never = firstValue(EmptyCollection<Deferred<Any>>.Iterator())
    do {
      let value = try never.get()
      XCTFail("never.value should be nil, was \(value)")
    }
    catch DeferredError.invalid(let m) {
      XCTAssert(m != "")
    }
  }

  func testFirstValueSequenceError() throws
  {
    func noValue(_ c: Int) -> Deferred<Int>
    {
      let deferreds = (0..<c).map {
        i -> Deferred<Int> in
        let e = expectation(description: String(i))
        return DeallocTBD(e, task: { $0.resolve(error: TestError(i)) })
      }
      return firstValue(deferreds.makeIterator())
    }

    let count = 10
    let first = noValue(count)
    XCTAssertEqual(first.error, TestError(count-1))

    waitForExpectations(timeout: 0.1)
  }

  func testFirstResolvedCollection1() throws
  {
    func resolution(_ c: Int) -> ([Resolver<Int>], Deferred<Int>)
    {
      var r: [Resolver<Int>] = []
      var d: [Deferred<Int>] = []
      for i in 0...c
      {
        let tbd = DeallocTBD(self.expectation(description: String(i)), task: { r.append($0) })
        d.append(tbd)
      }
      return (r, firstResolved(d, qos: .utility, cancelOthers: false).flatten().timeout(seconds: 0.2))
    }

    let count = 10
    let (r, f) = resolution(count)

    let e = Int.random(in: 1..<count)
    r[e].resolve(value: e)

    waitForExpectations(timeout: 0.1)

    XCTAssertEqual(try f.get(), e)
  }

  func testFirstResolvedCollection2() throws
  {
    func resolution(_ c: Int) -> ([Resolver<Int>], Deferred<Int>)
    {
      var r: [Resolver<Int>] = []
      var d: [Deferred<Int>] = []
      for i in 0...c
      {
        let tbd = DeallocTBD(self.expectation(description: String(i)), task: { r.append($0) }).validate(predicate: {$0 == i})
        let e = expectation(description: "Resolution \(i)")
        tbd.notify  {
          result in
          if result.value == i { e.fulfill() }
          else if result.error != nil
          {
            XCTAssertEqual(result.error, DeferredError.notSelected)
            e.fulfill()
          }
        }
        d.append(tbd)
      }
      return (r, firstResolved(d, qos: .utility, cancelOthers: true).flatten().timeout(seconds: 0.2))
    }

    let count = 10
    let (r, f) = resolution(count)

    let e = Int.random(in: 1..<count)
    r[e].resolve(value: e)

    waitForExpectations(timeout: 0.1)

    XCTAssertEqual(try f.get(), e)
  }

  func testFirstResolvedSequence1() throws
  {
    func sequence() -> AnyIterator<Deferred<Int>>
    {
      var delay = 1
      var deferreds = (1...3).map {
        i -> Deferred<Int> in
        defer { delay *= 10 }
        let e = expectation(description: String(i))
        return DeallocTBD(e) { $0.resolve(value: delay) }
      }

      return AnyIterator { () -> Deferred<Int>? in
        if deferreds.isEmpty { return nil }
        let d = deferreds.removeLast()
        return d.delay(.milliseconds(d.value!))
      }
    }

    let first = firstResolved(sequence(), cancelOthers: true).flatten()
    XCTAssertEqual(try? first.get(), 1)
    waitForExpectations(timeout: 0.1)
  }

  func testFirstResolvedSequence2() throws
  {
    let never = firstResolved(EmptyCollection<Deferred<Any>>.Iterator())
    do {
      let value = try never.get()
      XCTFail("never.value should be nil, was \(value)")
    }
    catch DeferredError.invalid {}
  }

  func testFirstResolvedSequence3() throws
  {
    func resolution(_ c: Int) -> ([Resolver<Int>], Deferred<Int>)
    {
      var r: [Resolver<Int>] = []
      var d: [Deferred<Int>] = []
      for i in 0...c
      {
        let tbd = DeallocTBD(self.expectation(description: String(i)), task: { r.append($0) }).validate(predicate: {$0 == i})
        d.append(tbd)
      }
      return (r, firstResolved(d.makeIterator(), qos: .utility).flatten().timeout(seconds: 0.2))
    }

    let count = 10
    let (r, f) = resolution(count)

    let e = Int.random(in: 1..<count)
    r[e].resolve(value: e)

    waitForExpectations(timeout: 0.1)

    XCTAssertEqual(try f.get(), e)
  }

  func testSelectFirstResolved1()
  {
    let e1 = expectation(description: #function + "1")
    let e2 = expectation(description: #function + "2")
    let r2 = nzRandom()
    var t2: Resolver<Int>! = nil

    let (s1, s2) = firstResolved(DeallocTBD(e1) { _ in },
                                 DeallocTBD(e2) { t2 = $0 },
                                 canceling: true)
    s1.notify { XCTAssertEqual($0.error, DeferredError.notSelected) }
    s2.notify { XCTAssertEqual($0.value, r2) }

    t2.resolve(value: r2)

    waitForExpectations(timeout: 0.1)
  }

  func testSelectFirstResolved2()
  {
    let r = nzRandom()
    let e1 = expectation(description: #function)
    var r2: Resolver<Double>! = nil

    let (s1, s2) = firstResolved(Deferred(value: r), TBD<Double>(qos: .utility) { r2 = $0 })
    s1.notify { XCTAssertEqual($0.value, r) }
    s1.notify { _ in e1.fulfill() }
    s2.notify { XCTAssertEqual($0.error, DeferredError.notSelected) }

    waitForExpectations(timeout: 0.1)
    XCTAssertEqual(r2.needsResolution, false)
  }

  func testSelectFirstValue1()
  {
    let d1 = TBD<Int>() { _ in }
    let (t2, d2) = TBD<Double>.CreatePair(qos: .utility)

    let e2 = expectation(description: #function)

    let (s1, s2) = firstValue(d1, d2, canceling: true)
    s1.notify { XCTAssertEqual($0.error, DeferredError.notSelected) }
    s2.notify { $0.value.map { _ in e2.fulfill() } }

    t2.resolve(value: .pi)

    waitForExpectations(timeout: 0.1)
    XCTAssertEqual(d1.error, DeferredError.notSelected)
  }

  func testSelectFirstValue2()
  {
    let r = Double(nzRandom())
    let e1 = expectation(description: #function + "1")
    let e2 = expectation(description: #function + "2")

    let (s1, s2) = firstValue(Deferred(value: r), DeallocTBD(e2))
    s1.onValue { XCTAssertEqual($0, r) }
    s1.notify { _ in e1.fulfill() }
    s2.notify { XCTAssertEqual($0.error, DeferredError.notSelected) }

    waitForExpectations(timeout: 0.1)
  }

  func testSelectFirstValue3()
  {
    let r1 = nzRandom()
    let r2 = nzRandom()
    let e2 = expectation(description: #function)

    let (s1, s2) = firstValue(Deferred<Int>(error: TestError(r1)),
                              DeallocTBD(e2, task: { $0.resolve(error: TestError(r2)) }))
    s1.notify { XCTAssertEqual($0.error, TestError(r1)) }
    s2.notify { XCTAssertEqual($0.error, TestError(r2)) }

    waitForExpectations(timeout: 0.1)
  }
}
