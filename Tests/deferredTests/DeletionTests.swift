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

@testable import deferred

class DeletionTests: XCTestCase
{
  static var allTests = [
    ("testDeallocDeferred1", testDeallocDeferred1),
    ("testDeallocDeferred2", testDeallocDeferred2),
    ("testDeallocTBD1", testDeallocTBD1),
    ("testDeallocTBD2", testDeallocTBD2),
  ]

  class Dealloc: Deferred<Void>
  {
    let e: XCTestExpectation
    init(expectation: XCTestExpectation)
    {
      e = expectation
      super.init(queue: DispatchQueue.global())
    }
    deinit
    {
      e.fulfill()
    }
  }

  func testDeallocDeferred1()
  {
    do {
      let deferred = Dealloc(expectation: expectation(description: "will dealloc deferred 1"))
      do { deferred.notify { _ in XCTFail("Unexpected notification") } }
    }

    waitForExpectations(timeout: 0.1)
  }

  func testDeallocDeferred2()
  {
    do {
      Dealloc(expectation: expectation(description: "will dealloc deferred 2")).cancel()
    }

    waitForExpectations(timeout: 0.1)
  }

  class DeallocTBD: TBD<Void>
  {
    let e: XCTestExpectation
    init(expectation: XCTestExpectation)
    {
      e = expectation
      super.init(queue: DispatchQueue.global())
    }
    deinit
    {
      e.fulfill()
    }
  }

  func testDeallocTBD1()
  {
    do {
      let tbd = DeallocTBD(expectation: expectation(description: "will dealloc tbd 1"))
      do { tbd.notify { _ in XCTFail("Unexpected notification") } }
    }

    waitForExpectations(timeout: 0.1)
  }

  func testDeallocTBD2()
  {
    do {
      DeallocTBD(expectation: expectation(description: "will dealloc tbd 2")).cancel()
    }

    waitForExpectations(timeout: 0.1)
  }
}
