//
//  DeferredExamples.swift
//  deferred
//
//  Created by Guillaume Lessard on 2019-11-21.
//  Copyright © 2019-2020 Guillaume Lessard. All rights reserved.
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

    result3.onValue { print("Result 3 is: \($0)") }

    let result4 = combine(result1, result2)

    let result5 = result2.map(transform: Double.init).timeout(.milliseconds(50))

    print("Waiting")
    print("Result 1: \(result1.value!)")
    XCTAssertEqual(result1.value, 10.5)
    print("Result 2: \(result2.value!)")
    XCTAssertEqual(result2.value, 21)
    print("Result 3: \(result3.value!)")
    XCTAssertEqual(result3.value, String(3*result1.value!))
    print("Result 4: \(result4.value!)")
    XCTAssertEqual(result4.value?.0, result1.value)
    XCTAssertEqual(result4.value?.1, result2.value)
    print("Result 5: \(result5.error!)")
    XCTAssertEqual(result5.value, nil)
    XCTAssertEqual(result5.error, Cancellation.timedOut(""))
    print("Done")

    XCTAssertEqual(result1.error, nil)
    XCTAssertEqual(result2.error, nil)
    XCTAssertEqual(result3.error, nil)
    XCTAssertEqual(result4.error, nil)
    XCTAssertEqual(result5.value, nil)
  }

  func testExample2()
  {
    let d = Deferred<Double, Never> {
      resolver in
      usleep(50000)
      resolver.resolve(.success(.pi))
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

  func testBigComputation() throws
  {
    func bigComputation() -> Deferred<Double, Never>
    {
      return Deferred {
        resolver in
        DispatchQueue.global(qos: .utility).async {
          var progress = 0
          repeat {
            // first check that a result is still needed
            guard resolver.needsResolution else { return }
            // then work towards a partial computation
            Thread.sleep(until: Date() + 0.001)
            print(".", terminator: "")
            progress += 1
          } while progress < 20
          // we have an answer!
          resolver.resolve(value: .pi)
        }
      }
    }

    // let the child `Deferred` keep a reference to our big computation
    let validated = bigComputation().validate(predicate: { $0 > 3.14159 && $0 < 3.14160 })
    let timeout = 0.1
    validated.timeout(seconds: timeout, reason: String(timeout))

    do {
      print(validated.state)       // still waiting: no request yet
      let pi = try validated.get() // make the request and wait for value
      print(" ", pi)
    }
    catch Cancellation.timedOut(let message) {
      print()
      assert(message == String(timeout))
    }
  }
}
