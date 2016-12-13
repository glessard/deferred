//
//  TBDTests.swift
//  async-deferred-tests
//
//  Created by Guillaume Lessard on 2015-07-28.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation
import Dispatch

import deferred


class TBDTests: XCTestCase
{
  static var allTests: [(String, (TBDTests) -> () throws -> Void)] {
    return [
      ("testDetermine1", testDetermine1),
      ("testDetermine2", testDetermine2),
      ("testCancel", testCancel),
      ("testDealloc", testDealloc),
      ("testNotify1", testNotify1),
      ("testNotify2", testNotify2),
      ("testNotify3", testNotify3),
      ("testNeverDetermined", testNeverDetermined),
      ("testFirstValue", testFirstValue),
      ("testFirstDetermined", testFirstDetermined),
      ("testParallel1", testParallel1),
      ("testParallel2", testParallel2),
      ("testParallel3", testParallel3),
    ]
  }

  func testDetermine1()
  {
    let tbd = TBD<UInt32>()
    tbd.beginExecution()
    let value = nzRandom()
    do { try tbd.determine(value) }
    catch { XCTFail() }
    XCTAssert(tbd.isDetermined)
    XCTAssert(tbd.value == value)
    XCTAssert(tbd.error == nil)

    let tbe = TBD<Void>()
    tbe.beginExecution()
    do { try tbe.determine(TestError(value)) }
    catch { XCTFail() }
    XCTAssert(tbe.isDetermined)
    XCTAssert(tbe.value == nil)
    XCTAssert(tbe.error as? TestError == TestError(value))
  }

  func testDetermine2()
  {
    let tbd = TBD<UInt32>()
    tbd.beginExecution()
    var value = nzRandom()
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.01) {
      value = nzRandom()
      do { try tbd.determine(value) }
      catch { XCTFail() }
    }

    XCTAssert(tbd.isDetermined == false)

    // Block until tbd becomes determined
    XCTAssert(tbd.value == value)
    XCTAssert(tbd.error == nil)

    // Try and fail to determine tbd a second time.
    do {
      try tbd.determine(value)
      XCTFail()
    }
    catch let error as DeferredError {
      _ = String(describing: error)
      if case let .alreadyDetermined(message) = error
      {
        XCTAssert(error == .alreadyDetermined(message))
      }
    }
    catch { XCTFail() }
  }

  func testCancel()
  {
    let tbd1 = TBD<Void>()
    let reason = "unused"
    tbd1.cancel(reason)
    XCTAssert(tbd1.value == nil)
    switch tbd1.result
    {
    case .value: XCTFail()
    case .error(let error):
      if let e = error as? DeferredError, case .canceled(let message) = e
      {
        XCTAssert(message == reason)
      }
      else { XCTFail() }
    }

    let e = expectation(description: "Cancel before setting")
    let tbd3 = TBD<UInt32>()
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.1) { XCTAssert(tbd3.cancel() == true) }
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.2) {
      do {
        try tbd3.determine(nzRandom())
        XCTFail()
      }
      catch DeferredError.alreadyDetermined {
        e.fulfill()
      }
      catch {
        XCTFail()
      }
    }

    waitForExpectations(timeout: 1.0)
  }

  func testDealloc()
  {
    class DeallocTBD: TBD<Void>
    {
      let e: XCTestExpectation
      init(expectation: XCTestExpectation)
      {
        e = expectation
        super.init(queue: DispatchQueue.global())
      }
      deinit
      {
        e.fulfill()
      }
    }

    do {
      // This will get deallocated because notify doesn't create reference cycles
      let tbd = DeallocTBD(expectation: expectation(description: "will dealloc"))
      for i in 1...3 { tbd.notify { _ in XCTFail("Notification \(i)") } }
    }

    waitForExpectations(timeout: 0.1)
  }

  func testNotify1()
  {
    let value = nzRandom()
    let e1 = expectation(description: "TBD notification after determination")
    let tbd = TBD<UInt32>()
    try! tbd.determine(value)

    tbd.notify {
      XCTAssert( $0 == Result.value(value) )
      e1.fulfill()
    }
    waitForExpectations(timeout: 1.0)
  }

  func testNotify2()
  {
    let e2 = expectation(description: "TBD notification after delay")
    let tbd = TBD<UInt32>()

    var value = nzRandom()
    tbd.notify {
      XCTAssert( $0 == Result.value(value) )
      e2.fulfill()
    }

    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 10e-6) {
      value = nzRandom()
      do { try tbd.determine(value) }
      catch { XCTFail() }
    }

    waitForExpectations(timeout: 1.0)
  }

  func testNotify3()
  {
    let e3 = expectation(description: "TBD never determined")
    let d3 = TBD<Int>()
    d3.notify {
      result in
      do {
        _ = try result.getValue()
        XCTFail()
      }
      catch DeferredError.canceled {}
      catch { XCTFail() }
    }
    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.2) {
      // This will trigger the `XCWaitCompletionHandler` in the `waitForExpectationsWithTimeout` call below.
      e3.fulfill()
    }
    waitForExpectations(timeout: 1.0) { _ in d3.cancel() }
  }

  func testNeverDetermined()
  {
    // a Deferred that will never become determined.
    let first = TBD<Int>()

    let other = first.map { XCTFail(String($0)) }
    let third = other.map { XCTFail() }

    usleep(1000)

    XCTAssert(first.isDetermined == false)
    XCTAssert(other.isDetermined == false)
    XCTAssert(third.isDetermined == false)

    first.cancel()

    XCTAssertNil(first.value)
    XCTAssertNil(other.value)
    XCTAssertNil(third.value)
  }

  func testFirstValue()
  {
    let count = 10
    let lucky = Int(nzRandom()) % count

    let deferreds = (0..<count).map { _ in TBD<Int>() }
    let first1 = firstValue(deferreds)
    let first2 = firstValue(AnySequence(deferreds.map({$0 as Deferred})))

    do { try deferreds[lucky].determine(lucky) }
    catch { XCTFail() }

    XCTAssert(first1.value == lucky)
    XCTAssert(first2.value == lucky)

    for (i,d) in deferreds.enumerated()
    {
      do { try d.determine(i) }
      catch { XCTAssert(i == lucky) }
    }

    _ = deferreds.map { d in d.cancel() }

    let never = firstValue([Deferred<Any>]())
    XCTAssert(never.value == nil)
    XCTAssert(never.error is DeferredError)
  }

  func testFirstDetermined()
  {
    let count = 10

    let deferreds = (0..<count).map {
      i -> Deferred<Int> in
      let e = expectation(description: i.description)
      return Deferred {
        _ in
        usleep(numericCast(i)*10_000)
        e.fulfill()
        return i
      }
    }

    func oneBy1(_ deferreds: [Deferred<Int>])
    {
      let first = firstDetermined(deferreds)
      if let index = deferreds.index(where: { d in d === first.value })
      {
        var d = deferreds
        d.remove(at: index)
        oneBy1(d)
      }

      if deferreds.count == 0
      {
        XCTAssert(first.value == nil)
        XCTAssert(first.error is DeferredError)
      }
    }

    oneBy1(deferreds)
    waitForExpectations(timeout: 1.0)
  }

  func testParallel1()
  {
    let count = 10

    // Verify that the right number of Deferreds get created

    let e = (0..<count).map { expectation(description: "\($0)") }
    _ = Deferred.inParallel(count: count, qos: .utility) { i in e[i].fulfill() }
    waitForExpectations(timeout: 1.0)
  }

  func testParallel2()
  {
    let count = 10

    // Verify that all created Deferreds do the right job

    let arrays = Deferred.inParallel(count: count) {
      index in
      (0..<count).map { i in index*count+i }
    }

    let e = expectation(description: "e")
    let determined = combine(arrays).map { $0.flatMap({$0}) }
    determined.notify { _ in e.fulfill() }
    XCTAssert(determined.value?.count == count*count)

    determined.value?.enumerated().forEach { XCTAssert($0 == $1, "\($0) should equal \($1)") }

    waitForExpectations(timeout: 1.0)
  }

  func testParallel3()
  {
    // Verify that "accidentally" passing a serial queue to inParallel doesn't cause a deadlock

    let q = DispatchQueue(label: "test1", qos: .utility)

    let count = 20
    let e = expectation(description: "e")
    let d = Deferred.inParallel(count: count, queue: q) { $0 }
    let c = combine(d)
    c.notify { _ in e.fulfill() }
    XCTAssert(c.value?.count == count)

    waitForExpectations(timeout: 1.0)
  }
}
