//
//  TBDTests.swift
//  async-deferred-tests
//
//  Created by Guillaume Lessard on 2015-07-28.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest

import async_deferred

class TBDTests: XCTestCase
{
  func testDetermine()
  {
    let tbd = TBD<UInt32>()
    let value = arc4random()
    do { try tbd.determine(value) }
    catch { XCTFail() }
    XCTAssert(tbd.value == value)
  }

  func testFirstCompletedDeferred()
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

    let first = firstCompleted(deferreds)
    XCTAssert(first.value == lucky)
    waitForExpectationsWithTimeout(1.0, handler: nil)
  }

  func testFirstCompletedTBD()
  {
    let count = 10
    let lucky = Int(arc4random_uniform(numericCast(count)))

    let deferreds = (0..<count).map { _ in TBD<Int>() }
    let first = firstCompleted(deferreds)

    do { try deferreds[lucky].determine(lucky) }
    catch { XCTFail() }

    for (i,d) in deferreds.enumerate()
    {
      do { try d.determine(i) }
      catch { XCTAssert(i == lucky) }
    }

    XCTAssert(first.value == lucky)
  }
}