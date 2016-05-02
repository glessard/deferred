//
//  TBDTimingTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 29/04/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest

import deferred


class TBDTimingTests: XCTestCase
{
  func testPerformancePropagationTime()
  {
    measure {
      let iterations = 10_000
      let ref = NSDate.distantPast()

      let first = TBD<(Int, NSDate, NSDate)>(qos: QOS_CLASS_USER_INITIATED)
      var dt: Deferred = first
      for _ in 0...iterations
      {
        dt = dt.map {
          (i, tic, toc) in
          tic == ref ? (0, NSDate(), ref) : (i+1, tic, NSDate())
        }
      }

      try! first.determine( (0, ref, ref) )

      switch dt.result
      {
      case let .value(iterations, tic, toc):
        let interval = toc.timeIntervalSince(tic)
        // print("\(round(Double(interval*1e9)/Double(iterations))/1000) µs per message")
        _ = interval/Double(iterations)
        break
        
      default: XCTFail()
      }
    }
  }

  func testPerformanceNotificationTime()
  {
    measure {
      let iterations = 10_000

      let attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0)
      let start = TBD<NSDate>(queue: dispatch_queue_create("", attr))
      for _ in 0..<iterations
      {
        start.notify { _ in }
      }

      let dt = start.map { start in NSDate().timeIntervalSince(start) }
      try! start.determine(NSDate())

      switch dt.result
      {
      case .value(let interval):
        // print("\(round(Double(interval*1e9)/Double(iterations))/1000) µs per notification")
        _ = interval
        break
        
      default: XCTFail()
      }
    }
  }
  
}