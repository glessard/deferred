import XCTest

import deferredTests

var tests = [XCTestCaseEntry]()
tests += deferredTests.__allTests()

XCTMain(tests)
