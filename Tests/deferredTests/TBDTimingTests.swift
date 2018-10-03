//
//  TBDTimingTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 29/04/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation
import Dispatch

import deferred


class TBDTimingTests: XCTestCase
{
  let propagationTestCount = 10_000

  func testPerformancePropagationTime()
  {
    let iterations = propagationTestCount
    let ref = Date.distantPast

    measure {
      let first = TBD<(Int, Date, Date)>(qos: .userInitiated)
      var dt: Deferred = first
      for _ in 0...iterations
      {
        let prev = dt
        dt = prev.map {
          (i, tic, toc) in
          tic == ref ? (0, Date(), ref) : (i+1, tic, Date())
        }
      }

      first.determine(value: (0, ref, ref))

      let (iterations, tic, toc) = try! dt.get()
      let interval = toc.timeIntervalSince(tic)
      // print("\(round(Double(interval*1e9)/Double(iterations))/1000) µs per message")
      _ = interval/Double(iterations)
    }
  }

  func testPerformanceNotificationTime()
  {
    let iterations = propagationTestCount

    measure {
      let start = TBD<Date>(queue: DispatchQueue(label: "", qos: .userInitiated))
      for _ in 0..<iterations
      {
        start.notify { deferred in _ = deferred.value! }
      }

      let dt = start.map { start in Date().timeIntervalSince(start) }
      start.determine(value: Date())

      let interval = try! dt.get()
      // print("\(round(Double(interval*1e9)/Double(iterations))/1000) µs per notification")
      _ = interval
    }
  }
}
