//
//  DeletionTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 31/01/2017.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation
import Dispatch

import deferred

class DeletionTests: XCTestCase
{
  func testDelayedDeallocDeferred()
  {
    let witness: Deferred<Void>
    let e = expectation(description: "deallocation delay")
    do {
      let queue = DispatchQueue(label: "\(#function)")
      let delayed = Deferred(queue: queue, value: ()).delay(.milliseconds(50))
      _ = delayed.map { XCTFail("a value no one waits for should not be computed") }
      witness = delayed.map { e.fulfill() }
    }

    waitForExpectations(timeout: 1.0)
    _ = witness.value
  }

  func testDeallocTBD1()
  {
    do {
      _ = DeallocTBD<Void>(expectation(description: "will dealloc tbd 1"))
    }

    waitForExpectations(timeout: 1.0)
  }

  func testDeallocTBD2()
  {
    do {
      let tbd = DeallocTBD<Void>(expectation(description: "will dealloc tbd 2"))
      do { _ = tbd.map { _ in XCTFail("Unexpected notification") } }
      tbd.cancel()
    }

    waitForExpectations(timeout: 1.0)
  }

  func testDeallocTBD3()
  {
    do {
      DeallocTBD<Void>(expectation(description: "will dealloc tbd 3")).cancel()
    }

    waitForExpectations(timeout: 1.0)
  }

  func testDeallocTBD4()
  {
    let mapped: Deferred<Void> = {
      let deferred = DeallocTBD<Void>(expectation(description: "will dealloc tbd 4"))
      return deferred.map { _ in XCTFail("Unexpected notification") }
    }()
    mapped.cancel()

    waitForExpectations(timeout: 1.0)
  }

  func testLongTaskCancellation1() throws
  {
    func bigComputation() -> Deferred<Double>
    {
      let e = expectation(description: #function)
      return DeallocTBD<Double>(e) {
        resolver in
        DispatchQueue.global(qos: .utility).async {
          var progress = 0
          repeat {
            guard resolver.needsResolution else { return }
            Thread.sleep(until: Date() + 0.01) // work hard
            print(".", terminator: "")
            progress += 1
          } while progress < 20
          resolver.resolve(value: .pi)
        }
      }
    }

    let validated = bigComputation().validate(predicate: { $0 > 3.14159 && $0 < 3.14160 })
    let timeout = 0.1
    validated.timeout(seconds: timeout, reason: String(timeout))

    waitForExpectations(timeout: 1.0)

    do {
      let pi = try validated.get()
      print(" ", pi)
    }
    catch DeferredError.timedOut(let message) {
      print()
      XCTAssertEqual(message, String(timeout))
    }
  }

  func testLongTaskCancellation2()
  {
    let e = expectation(description: #function)

    let deferred = TBD<Void>(qos: .utility) {
      resolver in
      func segmentedTask()
      {
        if resolver.needsResolution
        {
          print(".", terminator: "")
          let queue = DispatchQueue.global(qos: resolver.qos.qosClass)
          queue.asyncAfter(deadline: .now() + 0.01, execute: segmentedTask)
          return
        }

        print()
        e.fulfill()
      }

      segmentedTask()
    }

    deferred.timeout(seconds: 0.1)
    waitForExpectations(timeout: 1.0)

    XCTAssertEqual(deferred.error, DeferredError.timedOut(""))
  }
}
