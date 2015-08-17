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
  }

  func testNotify1()
  {
    let value = arc4random()
    let e1 = expectationWithDescription("TBD notification after determination")
    let tbd = TBD<UInt32>()
    try! tbd.determine(value)

    tbd.notify {
      XCTAssert( $0 == value )
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
      XCTAssert( $0 == value )
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
    d3.notify { _ in
      XCTFail()
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200_000_000), dispatch_get_global_queue(qos_class_self(), 0)) {
      e3.fulfill()
    }
    waitForExpectationsWithTimeout(1.0, handler: nil)
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

    // a Deferred that will never become determined.
    let _ = firstValue([Deferred<Int>]())

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
    XCTAssert(determined.value.count == count*count)

    var test = [Int?](count: combined.value.count, repeatedValue: nil)
    determined.value.forEach { i in test[i] = i }
    test = test.flatMap({$0})
    XCTAssert(test.count == count*count)
  }
}
