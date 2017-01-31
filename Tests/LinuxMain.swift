import XCTest
@testable import deferredTests

XCTMain([
  testCase(ResultTests.allTests),
  testCase(AtomicsRaceTests.raceTests),
  testCase(DeferredTests.allTests),
  testCase(DeferredCombinationTests.allTests),
  testCase(DeferredCombinationTimedTests.allTests),
  testCase(DeletionTests.allTests),
  testCase(TBDTests.allTests),
  testCase(TBDTimingTests.allTests),
])
