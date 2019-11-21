//
//  DeferredExamples.swift
//  deferred
//
//  Created by Guillaume Lessard on 11/21/19.
//  Copyright © 2019 Guillaume Lessard. All rights reserved.
//

import Foundation

import XCTest
import Foundation
import Dispatch

import deferred

class DeferredExamples: XCTestCase
{
  func testExample()
  {
    print("Starting")

    let result1 = Deferred(task: {
      () -> Double in
      defer { print("Computing result1") }
      return 10.5
    }).delay(.milliseconds(50))

    let result2 = result1.map {
      (d: Double) -> Int in
      print("Computing result2")
      return Int(floor(2*d))
    }.delay(.milliseconds(500))

    let result3 = result1.map {
      (d: Double) -> String in
      print("Computing result3")
      return (3*d).description
    }

    result3.onResult { print("Result 3 is: \($0.value!)") }

    let result4 = combine(result1, result2)

    let result5 = result2.map(transform: Double.init).timeout(.milliseconds(50))

    print("Waiting")
    print("Result 1: \(result1.value!)")
    print("Result 2: \(result2.value!)")
    print("Result 3: \(result3.value!)")
    print("Result 4: \(result4.value!)")
    print("Result 5: \(result5.error!)")
    print("Done")

    XCTAssert(result1.error == nil)
    XCTAssert(result2.error == nil)
    XCTAssert(result3.error == nil)
    XCTAssert(result4.error == nil)
    XCTAssert(result5.value == nil)
  }

  func testExample2()
  {
    let d = Deferred<Double, Never> {
      usleep(50000)
      return Result.success(1.0)
    }
    print(d.value!)
  }

  func testExample3()
  {
    let transform = Deferred<(Int) -> Double, Never> { i in Double(7*i) } // Deferred<Int throws -> Double>
    let operand = Deferred<Int, Error>(value: 6).delay(seconds: 0.1)      // Deferred<Int>
    let result = operand.apply(transform: transform)                      // Deferred<Double>
    print(result.value!)                                                  // 42.0
  }
}
