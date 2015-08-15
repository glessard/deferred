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
    let value = arc4random()
    do { try tbd.determine(value) }
    catch { XCTFail() }
    XCTAssert(tbd.isDetermined)
    XCTAssert(tbd.value == value)
    XCTAssert(tbd.error == nil)

    let tbe = TBD<Void>()
    tbe.beginExecution()
    do { try tbe.determine(TestError.Error(value)) }
    catch { XCTFail() }
    XCTAssert(tbe.isDetermined)
    XCTAssert(tbe.value == nil)
    XCTAssert(tbe.error as? TestError == TestError.Error(value))
  }

  func testDetermine2()
  {
    let tbd = TBD<UInt32>()
    tbd.beginExecution()
    var value = arc4random()
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10_000_000), dispatch_get_global_queue(qos_class_self(), 0)) {
      value = arc4random()
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
        try tbd3.determine(arc4random())
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
    let value = arc4random()
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

    var value = arc4random()
    tbd.notify {
      XCTAssert( $0.value == value )
      e2.fulfill()
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10_000), dispatch_get_global_queue(qos_class_self(), 0)) {
      value = arc4random()
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
      guard case let .Error(e) = result,
        let deferredErr = e as? DeferredError,
        case .Canceled = deferredErr
        else
      {
        XCTFail()
        return
      }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200_000_000), dispatch_get_global_queue(qos_class_self(), 0)) {
      e3.fulfill()
    }
    waitForExpectationsWithTimeout(1.0) { _ in d3.cancel() }
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

  func testParallel()
  {
    let count = 10

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
  }
}
