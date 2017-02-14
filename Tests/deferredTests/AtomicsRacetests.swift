//
//  RacetestsAtomics.swift
//

import XCTest
import Dispatch

#if SWIFT_PACKAGE
  import Atomics
#else
  @testable import deferred
#endif

let iterations = 200_000//_000

struct Point { var x = 0.0, y = 0.0, z = 0.0 }

class AtomicsRaceTests: XCTestCase
{
  static var raceTests: [(String, (AtomicsRaceTests) -> () throws -> Void)] {
    return [
      ("testRaceCrash", testRaceCrash),
      ("testRacePointerCAS", testRacePointerLoadCAS),
    ]
  }

  func testRaceCrash()
  { // this version is guaranteed to crash with a double-free
    let q = DispatchQueue(label: "", attributes: .concurrent)

  #if false
    for _ in 1...iterations
    {
      var p: Optional = UnsafeMutablePointer<Point>.allocate(capacity: 1)
      let closure = {
        while true
        {
          if let c = p
          {
            p = nil
            c.deallocate(capacity: 1)
          }
          else // pointer is deallocated
          {
            break
          }
        }
      }

      q.async(execute: closure)
      q.async(execute: closure)
    }
  #else
    print("double-free crash disabled")
  #endif

    q.sync(flags: .barrier) {}
  }

  func testRacePointerLoadCAS()
  {
    let q = DispatchQueue(label: "", attributes: .concurrent)

    for _ in 1...iterations
    {
      var p = AtomicMutablePointer(UnsafeMutablePointer<Point>.allocate(capacity: 1))
      let closure = {
        var c = p.load()
        while true
        {
          if p.loadCAS(current: &c, future: nil, type: .weak, orderSwap: .release, orderLoad: .acquire),
            let c = c
          {
            c.deallocate(capacity: 1)
          }
          else // pointer is deallocated
          {
            break
          }
        }
      }

      q.async(execute: closure)
      q.async(execute: closure)
    }

    q.sync(flags: .barrier) {}
  }
}
