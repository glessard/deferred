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

    waitForExpectations(timeout: 0.5)
    _ = witness.value
  }

  class DeallocTBD: TBD<Void>
  {
    let e: XCTestExpectation
    init(expectation: XCTestExpectation)
    {
      e = expectation
      super.init(queue: .global()) { _ in }
    }
    deinit
    {
      e.fulfill()
    }
  }

  func testDeallocTBD1()
  {
    do {
      _ = DeallocTBD(expectation: expectation(description: "will dealloc tbd 1"))
    }

    waitForExpectations(timeout: 0.1)
  }

  func testDeallocTBD2()
  {
    do {
      let tbd = DeallocTBD(expectation: expectation(description: "will dealloc tbd 2"))
      do { _ = tbd.map { _ in XCTFail("Unexpected notification") } }
      tbd.cancel()
    }

    waitForExpectations(timeout: 0.1)
  }

  func testDeallocTBD3()
  {
    do {
      DeallocTBD(expectation: expectation(description: "will dealloc tbd 3")).cancel()
    }

    waitForExpectations(timeout: 0.1)
  }

  func testDeallocTBD4()
  {
    let mapped: Deferred<Void> = {
      let deferred = DeallocTBD(expectation: expectation(description: "will dealloc tbd 4"))
      return deferred.map { _ in XCTFail("Unexpected notification") }
    }()
    mapped.cancel()

    waitForExpectations(timeout: 0.1)
  }

  func testLongTaskCancellation()
  {
    func longTask(resolver: Resolver<Void>)
    {
      let e = expectation(description: "cooperative cancellation")
      DispatchQueue.global(qos: .userInitiated).async {
        while resolver.needsResolution
        {
          Thread.sleep(until: Date() + 0.01)
          print(".", terminator: "")
        }
        print()
        e.fulfill()
        resolver.resolve(error: TestError())
      }
    }

    let deferred = TBD<Void>(qos: .utility, task: longTask).map(transform: { () in nzRandom() })

    deferred.timeout(seconds: 0.1)
    waitForExpectations(timeout: 1.0)

    deferred.cancel()
    XCTAssert(deferred.error as? DeferredError == DeferredError.timedOut(""))
  }
}
