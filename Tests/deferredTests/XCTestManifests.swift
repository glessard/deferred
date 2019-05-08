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

extension DeferredSelectionTests {
    static let __allTests = [
        ("testFirstResolvedCollection1", testFirstResolvedCollection1),
        ("testFirstResolvedCollection2", testFirstResolvedCollection2),
        ("testFirstResolvedSequence1", testFirstResolvedSequence1),
        ("testFirstResolvedSequence2", testFirstResolvedSequence2),
        ("testFirstResolvedSequence3", testFirstResolvedSequence3),
        ("testFirstValueCollection", testFirstValueCollection),
        ("testFirstValueCollectionError", testFirstValueCollectionError),
        ("testFirstValueEmptyCollection", testFirstValueEmptyCollection),
        ("testFirstValueEmptySequence", testFirstValueEmptySequence),
        ("testFirstValueSequence", testFirstValueSequence),
        ("testFirstValueSequenceError", testFirstValueSequenceError),
        ("testSelectFirstResolvedBinary1", testSelectFirstResolvedBinary1),
        ("testSelectFirstResolvedBinary2", testSelectFirstResolvedBinary2),
        ("testSelectFirstResolvedQuaternary", testSelectFirstResolvedQuaternary),
        ("testSelectFirstResolvedTernary", testSelectFirstResolvedTernary),
        ("testSelectFirstValueBinary1", testSelectFirstValueBinary1),
        ("testSelectFirstValueBinary2", testSelectFirstValueBinary2),
        ("testSelectFirstValueBinary3", testSelectFirstValueBinary3),
        ("testSelectFirstValueQuaternary1", testSelectFirstValueQuaternary1),
        ("testSelectFirstValueQuaternary2", testSelectFirstValueQuaternary2),
        ("testSelectFirstValueTernary1", testSelectFirstValueTernary1),
        ("testSelectFirstValueTernary2", testSelectFirstValueTernary2),
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
        ("testCancelDelay", testCancelDelay),
        ("testCancelFlatMap", testCancelFlatMap),
        ("testCancelMap", testCancelMap),
        ("testCancelRecover", testCancelRecover),
        ("testDeferredError", testDeferredError),
        ("testEnqueuing", testEnqueuing),
        ("testExample", testExample),
        ("testExample2", testExample2),
        ("testExample3", testExample3),
        ("testFlatMap", testFlatMap),
        ("testFlatten", testFlatten),
        ("testGet", testGet),
        ("testMap", testMap),
        ("testNotifyWaiters", testNotifyWaiters),
        ("testOnResolution1", testOnResolution1),
        ("testOnResolution2", testOnResolution2),
        ("testOnResolution3", testOnResolution3),
        ("testOnValueAndOnError", testOnValueAndOnError),
        ("testOptional", testOptional),
        ("testPeek", testPeek),
        ("testQoS", testQoS),
        ("testRecover", testRecover),
        ("testRetrying1", testRetrying1),
        ("testRetrying2", testRetrying2),
        ("testRetryTask", testRetryTask),
        ("testSplit", testSplit),
        ("testState", testState),
        ("testTimeout", testTimeout),
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
        ("testLongTaskCancellation1", testLongTaskCancellation1),
        ("testLongTaskCancellation2", testLongTaskCancellation2),
    ]
}

extension TBDTests {
    static let __allTests = [
        ("testCancel", testCancel),
        ("testNeverResolved", testNeverResolved),
        ("testOnResolution1", testOnResolution1),
        ("testOnResolution2", testOnResolution2),
        ("testOnResolution3", testOnResolution3),
        ("testOnResolution4", testOnResolution4),
        ("testParallel1", testParallel1),
        ("testParallel2", testParallel2),
        ("testParallel3", testParallel3),
        ("testParallel4", testParallel4),
        ("testResolve1", testResolve1),
        ("testResolve2", testResolve2),
    ]
}

extension TBDTimingTests {
    static let __allTests = [
        ("testPerformanceNotificationCreationTime", testPerformanceNotificationCreationTime),
        ("testPerformanceNotificationExecutionTime", testPerformanceNotificationExecutionTime),
        ("testPerformancePropagationTime", testPerformancePropagationTime),
    ]
}

extension URLSessionResumeTests {
    static let __allTests = [
        ("testResumeAfterCancellation", testResumeAfterCancellation),
        ("testResumeWithEmptyData", testResumeWithEmptyData),
        ("testResumeWithMangledData", testResumeWithMangledData),
        ("testResumeWithNonsenseData", testResumeWithNonsenseData),
    ]
}

extension URLSessionTests {
    static let __allTests = [
        ("testData_Cancellation", testData_Cancellation),
        ("testData_DoubleCancellation", testData_DoubleCancellation),
        ("testData_NotFound", testData_NotFound),
        ("testData_OK", testData_OK),
        ("testData_Partial", testData_Partial),
        ("testData_Post", testData_Post),
        ("testData_SuspendCancel", testData_SuspendCancel),
        ("testDownload_Cancellation", testDownload_Cancellation),
        ("testDownload_DoubleCancellation", testDownload_DoubleCancellation),
        ("testDownload_NotFound", testDownload_NotFound),
        ("testDownload_OK", testDownload_OK),
        ("testDownload_SuspendCancel", testDownload_SuspendCancel),
        ("testInvalidDataTaskURL1", testInvalidDataTaskURL1),
        ("testInvalidDataTaskURL2", testInvalidDataTaskURL2),
        ("testInvalidDownloadTaskURL", testInvalidDownloadTaskURL),
        ("testInvalidUploadTaskURL1", testInvalidUploadTaskURL1),
        ("testInvalidUploadTaskURL2", testInvalidUploadTaskURL2),
        ("testUploadData_Cancellation", testUploadData_Cancellation),
        ("testUploadData_OK", testUploadData_OK),
        ("testUploadFile_OK", testUploadFile_OK),
    ]
}

#if !os(macOS)
public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(DeferredCombinationTests.__allTests),
        testCase(DeferredCombinationTimedTests.__allTests),
        testCase(DeferredSelectionTests.__allTests),
        testCase(DeferredTests.__allTests),
        testCase(DelayTests.__allTests),
        testCase(DeletionTests.__allTests),
        testCase(TBDTests.__allTests),
        testCase(TBDTimingTests.__allTests),
        testCase(URLSessionResumeTests.__allTests),
        testCase(URLSessionTests.__allTests),
    ]
}
#endif
