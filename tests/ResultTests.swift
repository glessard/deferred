//
//  ResultTests.swift
//  async-deferred-tests
//
//  Created by Guillaume Lessard on 2015-07-30.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest

import deferred


class ResultTests: XCTestCase
{
  func testInit()
  {
    let r1: Result<Void> = Result()
    do {
      try r1.getValue()
      XCTFail()
    }
    catch {
      XCTAssert(error is NoResult)
    }

    let r2: Result<Int> = Result()
    do {
      try r2.getValue()
      XCTFail()
    }
    catch {
      XCTAssert(error is NoResult)
    }
  }

  func testInitValue()
  {
    let val = arc4random() & 0x3fff_ffff
    let res = Result.Value(val)

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
    let err = TestError(arc4random() & 0x3fff_ffff)
    let res = Result<Int>.Error(err)

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
    let val = arc4random() & 0x3fff_ffff
    let res = Result { _ throws -> UInt32 in val }

    do {
      let v = try res.getValue()
      XCTAssert(v == val)
    }
    catch {
      XCTFail()
    }

    XCTAssert(res.description == val.description)
}

  func testInitClosureError()
  {
    let err = TestError(arc4random() & 0x3fff_ffff)
    let res = Result { _ throws -> UInt32 in throw err }

    do {
      _ = try res.getValue()
      XCTFail()
    }
    catch {
      XCTAssert(error as? TestError == err)
    }

    XCTAssert(res.description.hasSuffix("\(err)"))
  }

  func testMap()
  {
    let value = arc4random() & 0x3fff_ffff
    let goodres = Result.Value(value)

    // Good operand, good transform
    let r1 = goodres.map { Int($0)*2 }
    XCTAssert(r1 == Result.Value(Int(value)*2))

    // Good operand, transform throws
    let r2 = goodres.map { (i:UInt32) throws -> NSObject in throw TestError(i) }
    XCTAssert(r2 == Result.Error(TestError(value)))

    let badres = Result<Double>()

    // Bad operand, transform not used
    let r3 = badres.map { (d: Double) throws -> Int in XCTFail(); return 0 }
    XCTAssert(r3 == Result())
  }

  func testFlatMap()
  {
    let value = arc4random() & 0x3fff_ffff
    let goodres = Result.Value(value)

    // Good operand, good transform
    let r1 = goodres.flatMap { Result.Value(Int($0)*2) }
    XCTAssert(r1 == Result.Value(Int(value)*2))

    // Good operand, transform errors
    let r2 = goodres.flatMap { Result<Double>.Error(TestError($0)) }
    XCTAssert(r2 == Result.Error(TestError(value)))

    let badres = Result<Double>()

    // Bad operand, transform not used
    let r3 = badres.flatMap { _ in Result<String> { XCTFail(); return "" } }
    XCTAssert(r3 == Result())
  }

  func testRecover()
  {
    let value = arc4random() & 0x3fff_ffff
    let goodres = Result.Value(value)

    // Good operand, transform short-circuited
    let r1 = goodres.recover { e in Result.Value(value*2) }
    XCTAssert(r1 == Result.Value(value))

    let badres = Result<Double>()

    // Bad operand, transform throws
    let r2 = badres.recover { e in Result.Error(TestError(value)) }
    XCTAssert(r2 == Result.Error(TestError(value)))

    // Bad operand, transform executes
    let r3 = badres.recover { e in Result.Value(Double(value)) }
    XCTAssert(r3 == Result.Value(Double(value)))
  }

  func testApplyA()
  {
    let value = Int(arc4random() & 0x7fff + 10000)
    let error = arc4random() & 0x3fff_ffff

    // Good operand, good transform
    let o1 = Result.Value(value)
    let t1 = Result.Value { i throws in Double(value*i) }
    let r1 = o1.apply(t1)
    XCTAssert(r1 == Result.Value(Double(value*value)))

    // Bad operand: transform not applied
    let o2 = Result<Int>.Error(TestError(error))
    let t2 = Result.Value({ (i:Int) throws -> CGPoint in XCTFail(); return CGPointZero })
    let r2 = o2.apply(t2)
    XCTAssert(r2 == Result.Error(TestError(error)))

    // Good operand, transform Result carries error
    let o4 = Result.Value(value)
    let t4 = Result.Error(TestError(error)) as Result<(Int) throws -> UnsafeMutablePointer<AnyObject>>
    let r4 = o4.apply(t4)
    XCTAssert(r4 == Result.Error(TestError(error)))
  }

  func testApplyB()
  {
    let value = Int(arc4random() & 0x7fff + 10000)
    let error = arc4random() & 0x3fff_ffff

    // Good operand, good transform
    let o1 = Result.Value(value)
    let t1 = Result.Value { i in Result.Value(Double(value*i)) }
    let r1 = o1.apply(t1)
    XCTAssert(r1 == Result.Value(Double(value*value)))

    // Bad operand: transform not applied
    let o2 = Result<Int>.Error(TestError(error))
    let t2 = Result.Value { (i:Int) in Result<CGPoint> { XCTFail(); return CGPointZero } }
    let r2 = o2.apply(t2)
    XCTAssert(r2 == Result.Error(TestError(error)))

    // Good operand, transform Result carries error
    let o4 = Result.Value(value)
    let t4 = Result.Error(TestError(error)) as Result<(Int) -> Result<UnsafeMutablePointer<AnyObject>>>
    let r4 = o4.apply(t4)
    XCTAssert(r4 == Result.Error(TestError(error)))
  }

  func testQuestionMarkQuestionMarkOperator()
  {
    let r1 = Result.Value(Int(arc4random() & 0x3fff_fff0 + 1))
    let v1 = r1 ?? -1
    XCTAssert(v1 > 0)

    let r2 = Result<Int>.Error(TestError(arc4random() & 0x3fff_ffff))
    let v2 = r2 ?? -1
    XCTAssert(v2 < 0)
  }

  func testEquals()
  {
    let r1 = Result { 100-99 }
    XCTAssert(r1 == Result.Value(1))

    let r2 = Result<Int> { throw TestError() }
    XCTAssert(r2 == Result.Error(TestError()))

    XCTAssert(r1 != r2)
  }

  func testEquals2()
  {
    let a1 = (0..<5).map { Result.Value($0) }
    let a2 = (1...5).map { Result.Value($0) }
    let a3 = a2.map { $0.map { $0 - 1 } }

    XCTAssert(a1 != a2)
    XCTAssert(a1 == a3)
    XCTAssert(a1 != [])
  }
}
