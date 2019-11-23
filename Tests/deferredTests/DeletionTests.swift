//
//  DeletionTests.swift
//  deferred
//
//  Created by Guillaume Lessard
//  Copyright © 2017-2019 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation
import Dispatch

import deferred

class DeallocWitness<T, F: Error>: Deferred<T, F>
{
  let e: XCTestExpectation

  init(_ expectation: XCTestExpectation, resolve: @escaping (Resolver<T, F>) -> Void = { _ in })
  {
    e = expectation
    let q = DispatchQueue.global(qos: .current ?? .default)
    super.init(queue: q, resolve: resolve)
  }

  deinit {
    e.fulfill()
  }
}

class DeletionTests: XCTestCase
{
  func testDelayedDeallocDeferred()
  {
    let witness: Deferred<Void, Never>
    let e = expectation(description: "deallocation delay")
    do {
      let queue = DispatchQueue(label: "\(#function)")
      let delayed = Deferred<Void, Never>(queue: queue, value: ()).delay(.milliseconds(50))
      _ = delayed.map { XCTFail("a value no one waits for should not be computed") }
      witness = delayed.map { e.fulfill() }
    }

    witness.onValue { _ in }
    waitForExpectations(timeout: 1.0)
  }

  func testDeallocTBD1()
  {
    do {
      _ = DeallocWitness<Void, Never>(expectation(description: "will dealloc tbd 1"))
    }

    waitForExpectations(timeout: 1.0)
  }

  func testDeallocTBD2()
  {
    do {
      let tbd = DeallocWitness<Void, Never>(expectation(description: "will dealloc tbd 2"))
      do { _ = tbd.map { _ in XCTFail("Unexpected notification") } }
      tbd.cancel()
    }

    waitForExpectations(timeout: 1.0)
  }

  func testDeallocTBD3()
  {
    do {
      DeallocWitness<Void, Cancellation>(expectation(description: "will dealloc tbd 3")).cancel()
    }

    waitForExpectations(timeout: 1.0)
  }

  func testDeallocTBD4()
  {
    let mapped: Deferred<Void, Cancellation> = {
      let deferred = DeallocWitness<Void, Cancellation>(expectation(description: "will dealloc tbd 4"))
      return deferred.map { _ in XCTFail("Unexpected notification") }
    }()
    mapped.cancel()
    mapped.onError { _ in }

    waitForExpectations(timeout: 1.0)
  }

  func testLongTaskCancellation1() throws
  {
    func bigComputation() -> Deferred<Double, Cancellation>
    {
      let e = expectation(description: #function)
      return DeallocWitness<Double, Cancellation>(e) {
        resolver in
        DispatchQueue.global(qos: .utility).async {
          var progress = 0
          repeat {
            guard resolver.needsResolution else { return }
            Thread.sleep(until: Date() + 0.001) // work hard
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

    do {
      let pi = try validated.get()
      print(" ", pi)
    }
    catch Cancellation.timedOut(let message) {
      print()
      XCTAssertEqual(message, String(timeout))
    }

    waitForExpectations(timeout: 1.0)
  }

  func testLongTaskCancellation2()
  {
    let e = expectation(description: #function)

    let deferred = Deferred<Void, Cancellation>(qos: .utility) {
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
    XCTAssertEqual(deferred.error, Cancellation.timedOut(""))
    waitForExpectations(timeout: 1.0)
  }
}
