//
//  TBDTests.swift
//  async-deferred-tests
//
//  Created by Guillaume Lessard on 2015-07-28.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest

import deferred


class TBDTests: XCTestCase
{
  func testDetermine1()
  {
    let tbd = TBD<UInt32>()
    tbd.beginExecution()
    let value = arc4random() & 0x3fff_ffff
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
    var value = arc4random() & 0x3fff_ffff
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10_000_000), dispatch_get_global_queue(qos_class_self(), 0)) {
      value = arc4random() & 0x3fff_ffff
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
      _ = String(error)
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

    let e = expectationWithDescription("Cancel before setting")
    let tbd3 = TBD<UInt32>()
    Deferred(value: ()).delay(ms: 100).notify { _ in XCTAssert(tbd3.cancel() == true) }
    Deferred(value: ()).delay(ms: 200).notify { _ in
      do {
        try tbd3.determine(arc4random() & 0x3fff_ffff)
        XCTFail()
      }
      catch DeferredError.alreadyDetermined {
        e.fulfill()
      }
      catch {
        XCTFail()
      }
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testDealloc()
  {
    class NoDeallocTBD: TBD<Void>
    {
      init()
      {
        super.init(queue: dispatch_get_global_queue(qos_class_self(), 0))
      }
      deinit
      {
        XCTFail("This is expected to leak, therefore deinit shouldn't run")
      }
    }

    do {
      // This one will leak.
      let tbd = NoDeallocTBD()
      for i in 1...3 { tbd.notify { _ in XCTFail("Notification \(i)") } }
      // Every block enqueued by the notify method has an implied reference back to self.
      // The reference needs to be strong, otherwise chaining will fail.
    }

    class DeallocTBD: TBD<Void>
    {
      let e: XCTestExpectation
      init(expectation: XCTestExpectation)
      {
        e = expectation
        super.init(queue: dispatch_get_global_queue(qos_class_self(), 0))
      }
      deinit
      {
        e.fulfill()
      }
    }

    do {
      // This one will get deallocated
      let tbd = DeallocTBD(expectation: expectationWithDescription("will dealloc"))
      for i in 1...3
      {
        tbd.notifyWithBlock(dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS,
                                                  { XCTFail("Block \(i)") }))
      }
    }

    waitForExpectationsWithTimeout(0.1, handler: nil)
  }

  func testNotify1()
  {
    let value = arc4random() & 0x3fff_ffff
    let e1 = expectationWithDescription("TBD notification after determination")
    let tbd = TBD<UInt32>()
    try! tbd.determine(value)

    tbd.notify {
      XCTAssert( $0 == Result.value(value) )
      e1.fulfill()
    }
    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testNotify2()
  {
    let e2 = expectationWithDescription("TBD notification after delay")
    let tbd = TBD<UInt32>()

    var value = arc4random() & 0x3fff_ffff
    tbd.notify {
      XCTAssert( $0 == Result.value(value) )
      e2.fulfill()
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10_000), dispatch_get_global_queue(qos_class_self(), 0)) {
      value = arc4random() & 0x3fff_ffff
      do { try tbd.determine(value) }
      catch { XCTFail() }
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testNotify3()
  {
    let e3 = expectationWithDescription("TBD never determined")
    let d3 = TBD<Int>()
    d3.notify {
      result in
      do {
        try result.getValue()
        XCTFail()
      }
      catch DeferredError.canceled {}
      catch { XCTFail() }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200_000_000), dispatch_get_global_queue(qos_class_self(), 0)) {
      // This will trigger the `XCWaitCompletionHandler` in the `waitForExpectationsWithTimeout` call below.
      e3.fulfill()
    }
    waitForExpectationsWithTimeout(1.0) { _ in d3.cancel() }
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

    // Memory management note: when a `Deferred` has other `Deferred` dependent on it, it *must* be determined
    // in order for memory to be reclaimed. This is because the createNotificationBlock() method creates
    // a block with a strong reference to `self`. The reference must be strong in order to allow `Deferred`
    // objects to exist without an explicit reference, which in turns allows chained calls.
    // `cancel()` is a perfectly correct way to determine a `Deferred`.

    first.cancel()

    XCTAssertNil(first.value)
    XCTAssertNil(other.value)
    XCTAssertNil(third.value)
  }

  func testFirstValue()
  {
    let count = 10
    let lucky = Int(arc4random_uniform(numericCast(count)))

    let deferreds = (0..<count).map { _ in TBD<Int>() }
    let first = firstValue(deferreds)

    do { try deferreds[lucky].determine(lucky) }
    catch { XCTFail() }

    XCTAssert(first.value == lucky)

    for (i,d) in deferreds.enumerate()
    {
      do { try d.determine(i) }
      catch { XCTAssert(i == lucky) }
    }

    let never = firstValue([Deferred<Any>]())
    XCTAssert(never.value == nil)
    XCTAssert(never.error is NoResult)
  }

  func testFirstDetermined()
  {
    let count = 10

    let deferreds = (0..<count).map {
      i -> Deferred<Int> in
      let e = expectationWithDescription(i.description)
      return Deferred {
        _ in
        usleep(numericCast(i)*10_000)
        e.fulfill()
        return i
      }
    }

    func oneBy1(deferreds: [Deferred<Int>])
    {
      let first = firstDetermined(deferreds)
      if let index = deferreds.indexOf({ d in d === first.value })
      {
        var d = deferreds
        d.removeAtIndex(index)
        oneBy1(d)
      }

      if deferreds.count == 0
      {
        XCTAssert(first.value == nil)
        XCTAssert(first.error is NoResult)
      }
    }

    oneBy1(deferreds)
    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testParallel1()
  {
    let count = 10

    // Verify that the right number of Deferreds get created

    let e = (0..<count).map { expectationWithDescription("\($0)") }
    Deferred.inParallel(count: count, qos: QOS_CLASS_UTILITY) { i in e[i].fulfill() }
    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testParallel2()
  {
    let count = 10

    // Verify that all created Deferreds do the right job

    let arrays = Deferred.inParallel(count: count) {
      index in
      (0..<count).map { i in index*count+i }
    }

    let determined = combine(arrays).map { $0.flatMap({$0}) }
    XCTAssert(determined.value?.count == count*count)

    determined.value?.enumerate().forEach { XCTAssert($0 == $1, "\($0) should equal \($1)") }
  }

  func testParallel3()
  {
    // Verify that "accidentally" passing a serial queue to inParallel doesn't cause a deadlock

    let a = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0)
    let q = dispatch_queue_create("test1", a)

    let count = 20
    let d = Deferred.inParallel(count: count, queue: q) { $0 }
    let c = combine(d)
    XCTAssert(c.value?.count == count)
  }
}
