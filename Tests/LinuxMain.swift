import XCTest
@testable import deferredTests

XCTMain([
  testCase(ResultTests.allTests),
  testCase(AtomicsRaceTests.raceTests),
  testCase(DeferredTests.allTests),
  testCase(DeferredReduceTimingTests.allTests),
  testCase(TBDTests.allTests),
  testCase(TBDTimingTests.allTests),
])
