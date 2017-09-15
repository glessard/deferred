import XCTest
@testable import deferredTests

XCTMain([
  testCase(DeferredTests.allTests),
  testCase(DeferredCombinationTests.allTests),
  testCase(DeferredCombinationTimedTests.allTests),
  testCase(DeletionTests.allTests),
  testCase(DispatchUtilitiesTests.allTests),
  testCase(TBDTests.allTests),
  testCase(TBDTimingTests.allTests),
])
