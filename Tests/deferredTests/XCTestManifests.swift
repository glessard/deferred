import XCTest

extension DeferredCombinationTests {
    static let __allTests = [
        ("testCombine2", testCombine2),
        ("testCombine3", testCombine3),
        ("testCombine4", testCombine4),
        ("testCombineArray1", testCombineArray1),
        ("testCombineArray2", testCombineArray2),
        ("testReduce", testReduce),
        ("testReduceCancel", testReduceCancel),
    ]
}

extension DeferredCombinationTimedTests {
    static let __allTests = [
        ("testPerformanceABAProneReduce", testPerformanceABAProneReduce),
        ("testPerformanceCombine", testPerformanceCombine),
        ("testPerformanceReduce", testPerformanceReduce),
    ]
}

extension DeferredRacingTests {
    static let __allTests = [
        ("testFirstDeterminedCollection", testFirstDeterminedCollection),
        ("testFirstDeterminedSequence", testFirstDeterminedSequence),
        ("testFirstValueCollection", testFirstValueCollection),
        ("testFirstValueCollectionError", testFirstValueCollectionError),
        ("testFirstValueEmptyCollection", testFirstValueEmptyCollection),
        ("testFirstValueEmptySequence", testFirstValueEmptySequence),
        ("testFirstValueSequence", testFirstValueSequence),
        ("testFirstValueSequenceError", testFirstValueSequenceError),
    ]
}

extension DeferredTests {
    static let __allTests = [
        ("testApply", testApply),
        ("testApply1", testApply1),
        ("testApply2", testApply2),
        ("testApply3", testApply3),
        ("testCancel", testCancel),
        ("testCancelAndNotify", testCancelAndNotify),
        ("testCancelApply", testCancelApply),
        ("testCancelBind", testCancelBind),
        ("testCancelDelay", testCancelDelay),
        ("testCancelMap", testCancelMap),
        ("testDeferredError", testDeferredError),
        ("testExample", testExample),
        ("testExample2", testExample2),
        ("testExample3", testExample3),
        ("testFlatMap", testFlatMap),
        ("testFlatten", testFlatten),
        ("testGet", testGet),
        ("testMap", testMap),
        ("testNotify1", testNotify1),
        ("testNotify2", testNotify2),
        ("testNotify3", testNotify3),
        ("testNotify4", testNotify4),
        ("testOptional", testOptional),
        ("testPeek", testPeek),
        ("testQoS", testQoS),
        ("testRecover", testRecover),
        ("testRetrying1", testRetrying1),
        ("testRetrying2", testRetrying2),
        ("testRetryTask", testRetryTask),
        ("testState", testState),
        ("testTimeout", testTimeout),
        ("testTransfer", testTransfer),
        ("testValidate1", testValidate1),
        ("testValidate2", testValidate2),
        ("testValue", testValue),
        ("testValueBlocks", testValueBlocks),
        ("testValueUnblocks", testValueUnblocks),
    ]
}

extension DelayTests {
    static let __allTests = [
        ("testAbandonedDelay", testAbandonedDelay),
        ("testCancelDelay", testCancelDelay),
        ("testDelayError", testDelayError),
        ("testDelayValue", testDelayValue),
        ("testDistantFuture", testDistantFuture),
        ("testDistantFutureDelay", testDistantFutureDelay),
        ("testSourceSlowerThanDelay", testSourceSlowerThanDelay),
    ]
}

extension DeletionTests {
    static let __allTests = [
        ("testDeallocTBD1", testDeallocTBD1),
        ("testDeallocTBD2", testDeallocTBD2),
        ("testDeallocTBD3", testDeallocTBD3),
        ("testDeallocTBD4", testDeallocTBD4),
        ("testDelayedDeallocDeferred", testDelayedDeallocDeferred),
        ("testLongTaskCancellation", testLongTaskCancellation),
    ]
}

extension TBDTests {
    static let __allTests = [
        ("testCancel", testCancel),
        ("testDetermine1", testDetermine1),
        ("testDetermine2", testDetermine2),
        ("testNeverDetermined", testNeverDetermined),
        ("testNotify1", testNotify1),
        ("testNotify2", testNotify2),
        ("testNotify3", testNotify3),
        ("testNotify4", testNotify4),
        ("testParallel1", testParallel1),
        ("testParallel2", testParallel2),
        ("testParallel3", testParallel3),
        ("testParallel4", testParallel4),
    ]
}

extension TBDTimingTests {
    static let __allTests = [
        ("testPerformanceNotificationTime", testPerformanceNotificationTime),
        ("testPerformancePropagationTime", testPerformancePropagationTime),
    ]
}

#if !os(macOS)
public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(DeferredCombinationTests.__allTests),
        testCase(DeferredCombinationTimedTests.__allTests),
        testCase(DeferredRacingTests.__allTests),
        testCase(DeferredTests.__allTests),
        testCase(DelayTests.__allTests),
        testCase(DeletionTests.__allTests),
        testCase(TBDTests.__allTests),
        testCase(TBDTimingTests.__allTests),
    ]
}
#endif
