//
//  DeferredReduceTimingTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 30/01/2017.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import XCTest
import deferred

class DeferredReduceTimingTests: XCTestCase
{
  static var allTests: [(String, (DeferredReduceTimingTests) -> () throws -> Void)] {
    return [
      ("testPerformanceReduce", testPerformanceReduce),
      ("testPerformanceCombine", testPerformanceCombine),
    ]
  }

  let loopTestCount = 10_000

  func testPerformanceReduce()
  {
    let iterations = loopTestCount

    measure {
      let inputs = (1...iterations).map { Deferred(value: $0) }
      let c = reduce(inputs, initial: 0, combine: +)
      switch c.result
      {
      case .value(let v):
        XCTAssert(v == (iterations*(iterations+1)/2))
      default:
        XCTFail()
      }
    }
  }

  func testPerformanceCombine()
  {
    let iterations = loopTestCount

    measure {
      let inputs = (1...iterations).map { Deferred(value: $0) }
      let c = combine(inputs)
      switch c.result
      {
      case .value(let v):
        XCTAssert(v.count == iterations)
      default:
        XCTFail()
      }
    }
  }
}
