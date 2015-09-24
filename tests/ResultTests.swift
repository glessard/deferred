//
//  ResultTests.swift
//  async-deferred-tests
//
//  Created by Guillaume Lessard on 2015-07-30.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest

#if os(OSX)
  import async_deferred
#elseif os(iOS)
  import async_deferred_ios
#endif

enum TestError: ErrorType, Equatable
{
  case Error(UInt32)
}

func == (lhe: TestError, rhe: TestError) -> Bool
{
  switch (lhe, rhe)
  {
  case (.Error(let l), .Error(let r)):
    return l == r
  }
}

class ResultTests: XCTestCase
{
  func testInitValue()
  {
    let val = arc4random() & 0x7fff_ffff
    let res = Result.Value(val)
    XCTAssert(res.value == val)
    XCTAssert(res.error == nil)

    do {
      let v = try res.getValue()
      XCTAssert(v == val)
    }
    catch {
      XCTFail()
    }

    XCTAssert(res.description == val.description)
  }

  func testInitError()
  {
    let err = TestError.Error(arc4random() & 0x7fff_ffff)
    let res = Result<Int>.Error(err)
    XCTAssert(res.error as? TestError == err)
    XCTAssert(res.value == nil)

    do {
      _ = try res.getValue()
      XCTFail()
    }
    catch {
      XCTAssert(error as? TestError == err)
    }

    XCTAssert(res.description.hasSuffix("\(err)"))
  }

  func testInitClosureSuccess()
  {
    let val = arc4random() & 0x7fff_ffff
    let res = Result { _ throws -> UInt32 in val }
    XCTAssert(res.value == val)
    XCTAssert(res.error == nil)
  }

  func testInitClosureError()
  {
    let err = TestError.Error(arc4random() & 0x7fff_ffff)
    let res = Result { _ throws -> UInt32 in throw err }
    XCTAssert(res.error as? TestError == err)
    XCTAssert(res.value == nil)
  }

  func testMap()
  {
    let value = arc4random() & 0x7fff_ffff
    let goodres = Result.Value(value)

    // Good operand, good transform
    let r1 = goodres.map { Int($0)*2 }
    XCTAssert(r1.value == Int(value)*2)
    XCTAssert(r1.error == nil)

    // Good operand, transform throws
    let r2 = goodres.map { (i:UInt32) throws -> NSObject in throw TestError.Error(i) }
    XCTAssert(r2.value == nil)
    XCTAssert(r2.error as? TestError == TestError.Error(value))

    let badres = Result<Double>()

    // Bad operand, transform not used
    let r3 = badres.map { (d: Double) throws -> Int in XCTFail(); return 0 }
    XCTAssert(r3.value == nil)
    XCTAssert(r3.error != nil)
  }

  func testFlatMap()
  {
    let value = arc4random() & 0x7fff_ffff
    let goodres = Result.Value(value)

    // Good operand, good transform
    let r1 = goodres.flatMap { Result.Value(Int($0)*2) }
    XCTAssert(r1.value == Int(value)*2)
    XCTAssert(r1.error == nil)

    // Good operand, transform errors
    let r2 = goodres.flatMap { Result<Double>.Error(TestError.Error($0)) }
    XCTAssert(r2.value == nil)
    XCTAssert(r2.error as? TestError == TestError.Error(value))

    let badres = Result<Double>()

    // Bad operand, transform not used
    let r3 = badres.flatMap { _ in Result<String> { XCTFail(); return "" } }
    XCTAssert(r3.value == nil)
    XCTAssert(r3.error != nil)
  }

  func testApply()
  {
    let value = Int(arc4random() & 0xffff + 10000)
    let error = arc4random() & 0x7fff_ffff

    let transform = Result.Value { i throws -> Double in Double(value*i) }

    // Good operand, good transform
    let o1 = Result.Value(value)
    let r1 = o1.apply(transform)
    XCTAssert(r1.value == Double(value*value))
    XCTAssert(r1.error == nil)

    // Bad operand, good transform
    let o2 = Result<Int>.Error(TestError.Error(error))
    let r2 = o2.apply(transform)
    XCTAssert(r2.value == nil)
    XCTAssert(r2.error as? TestError == TestError.Error(error))

    // Good operand, transform throws
    let o3 = Result.Value(error)
    let t3 = Result.Value({ (i:UInt32) throws -> AnyObject in throw TestError.Error(i) })
    let r3 = o3.apply(t3)
    XCTAssert(r3.value == nil)
    XCTAssert(r3.error as? TestError == TestError.Error(error))

    // Good operand, bad transform
    let o4 = Result.Value(value)
    let t4 = Result.Error(TestError.Error(error)) as Result<(Int) throws -> UnsafeMutablePointer<AnyObject>>
    let r4 = o4.apply(t4)
    XCTAssert(r4.value == nil)
    XCTAssert(r4.error as? TestError == TestError.Error(error))

    // Operand error: transform not applied
    let o5 = Result<Int>.Error(TestError.Error(error))
    let t5 = Result.Value({ (i:Int) throws -> CGPoint in XCTFail(); return CGPointZero })
    let r5 = o5.apply(t5)
    XCTAssert(r5.value == nil)
    XCTAssert(r5.error as? TestError == TestError.Error(error))
  }

  func testQuestionMarkQuestionMarkOperator()
  {
    let r1 = Result.Value(Int(arc4random() & 0x7fff_fff0 + 1))
    let v1 = r1 ?? -1
    XCTAssert(v1 > 0)

    let r2 = Result<Int>.Error(TestError.Error(arc4random() & 0x7fff_ffff))
    let v2 = r2 ?? -1
    XCTAssert(v2 < 0)
  }
}
