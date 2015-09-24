//
//  TBDTests.swift
//  async-deferred-tests
//
//  Created by Guillaume Lessard on 2015-07-28.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest

#if os(OSX)
  import async_deferred
#elseif os(iOS)
  import async_deferred_ios
#endif

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
    XCTAssert(tbd.value == value)
    XCTAssert(tbd.error == nil)
  }

  func testCancel()
  {
    let tbd1 = TBD<Void>()
    let reason = "unused"
    tbd1.cancel(reason)
    XCTAssert(tbd1.value == nil)
    switch tbd1.result
    {
    case .Value: XCTFail()
    case .Error(let error):
      if let e = error as? DeferredError, case .Canceled(let message) = e
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
      catch DeferredError.AlreadyDetermined {
        e.fulfill()
      }
      catch {
        XCTFail()
      }
    }

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testNotify1()
  {
    let value = arc4random() & 0x3fff_ffff
    let e1 = expectationWithDescription("TBD notification after determination")
    let tbd = TBD<UInt32>()
    try! tbd.determine(value)

    tbd.notify {
      XCTAssert( $0.value == value )
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
      XCTAssert( $0.value == value )
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
      catch DeferredError.Canceled {}
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
    let first = firstValue([Deferred<Int>]())
    XCTAssert(first.isDetermined == false)
  }

  func testNeverDetermined2()
  {
    let first = firstValue([Deferred<Int>]())

    let other = first.map { XCTFail(String($0)) }
    XCTAssert(other.isDetermined == false)

    let third = other.map { XCTFail() }
    XCTAssert(third.isDetermined == false)

    // Memory management note: when a `Deferred` has other `Deferred` dependent on it, it *must* be determined
    // in order for memory to be reclaimed. This is because the createNotificationBlock() method creates
    // a block with a strong reference to `self`. The reference must be strong in order to allow `Deferred`
    // objects to exist without an explicit reference, which in turns allows chained calls.
    // `cancel()` is a perfectly correct way to determine a `Deferred`.

    first.cancel()
  }

  func testFirstValueDeferred()
  {
    let count = 10
    let lucky = Int(arc4random_uniform(numericCast(count)))

    let deferreds = (0..<count).map {
      i -> Deferred<Int> in
      let e = expectationWithDescription(i.description)
      return Deferred {
        () -> Int in
        usleep(i == lucky ? 10_000 : 200_000)
        e.fulfill()
        return i
      }
    }

    let first = firstValue(deferreds)
    XCTAssert(first.value == lucky)

    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testFirstValueTBD()
  {
    let count = 10
    let lucky = Int(arc4random_uniform(numericCast(count)))

    let deferreds = (0..<count).map { _ in TBD<Int>() }
    let first = firstValue(deferreds)

    do { try deferreds[lucky].determine(lucky) }
    catch { XCTFail() }

    for (i,d) in deferreds.enumerate()
    {
      do { try d.determine(i) }
      catch { XCTAssert(i == lucky) }
    }

    XCTAssert(first.value == lucky)
  }

  func testFirstDeterminedDeferred()
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
      index -> [Int?] in
      var output = [Int?](count: count, repeatedValue: nil)
      for i in 0..<output.count
      {
        output[i] = index*count+i
      }
      return output
    }

    let combined = combine(arrays).map { a in a.flatMap({$0}) }
    let determined = combined.map { a in a.flatMap({$0}) }
    XCTAssert(determined.value?.count == count*count)

    var test = [Int?](count: determined.value?.count ?? 0, repeatedValue: nil)
    determined.value?.forEach { i in test[i] = i }
    test = test.flatMap({$0})
    XCTAssert(test.count == count*count)

    let d = Deferred.inParallel(count: count) { _ in usleep(20_000) }
    d[numericCast(arc4random_uniform(numericCast(count)))].cancel()
    let c = combine(d)
    XCTAssert(c.value == nil)
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
