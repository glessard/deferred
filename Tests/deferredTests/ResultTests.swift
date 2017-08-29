//
//  ResultTests.swift
//  deferred-tests
//
//  Created by Guillaume Lessard on 2015-07-30.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest

import deferred


class ResultTests: XCTestCase
{
  static var allTests = [
    ("testInitValue", testInitValue),
    ("testInitError", testInitError),
    ("testInitClosureSuccess", testInitClosureSuccess),
    ("testInitClosureError", testInitClosureError),
    ("testInitOptional", testInitOptional),
    ("testAccessors", testAccessors),
    ("testMap", testMap),
    ("testFlatMap", testFlatMap),
    ("testRecover", testRecover),
    ("testApplyA", testApplyA),
    ("testApplyB", testApplyB),
    ("testQuestionMarkQuestionMarkOperator", testQuestionMarkQuestionMarkOperator),
    ("testEquals", testEquals),
    ("testEquals2", testEquals2),
  ]

  func testInitValue()
  {
    let val = nzRandom()
    let res = Result.value(val)

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
    let err = TestError(nzRandom())
    let res = Result<Int>.error(err)

    do {
      _ = try res.getValue()
      XCTFail()
    }
    catch {
      XCTAssert(error as? TestError == err)
    }

    XCTAssert(res.description.hasSuffix("\(err)"))
  }

  func testInitOptional()
  {
    let err = TestError(nzRandom())
    let val = nzRandom()
    var opt = Optional(val)

    let optsome = Result(opt, or: err)
    XCTAssert(optsome.value == val)
    XCTAssert(optsome.error == nil)

    opt = nil
    let optnone = Result(opt, or: err)
    XCTAssert(optnone.value == nil)
    XCTAssert(optnone.error as? TestError == err)
  }

  func testInitClosureSuccess()
  {
    let val = nzRandom()
    let res = Result { () throws -> UInt32 in val }

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
    let err = TestError(nzRandom())
    let res = Result<UInt32> { throw err }

    do {
      _ = try res.getValue()
      XCTFail()
    }
    catch {
      XCTAssert(error as? TestError == err)
    }

    XCTAssert(res.description.hasSuffix("\(err)"))
  }

  func testAccessors()
  {
    var res = Result<Int>.error(TestError())
    XCTAssert(res.value == nil)
    XCTAssert(res.isValue == false)
    XCTAssert(res.error is TestError)
    XCTAssert(res.isError)

    res = Result.value(0)
    XCTAssert(res.value == 0)
    XCTAssert(res.isValue)
    XCTAssert(res.error == nil)
    XCTAssert(res.isError == false)
  }

  func testMap()
  {
    var value = nzRandom()
    let goodres = Result.value(value)

    // Good operand, good transform
    let r1 = goodres.map { Int($0)*2 }
    XCTAssert(r1 == Result.value(Int(value)*2))

    // Good operand, transform throws
    let r2 = goodres.map { (i:UInt32) throws -> Double in throw TestError(i) }
    XCTAssert(TestError(value).matches(r2))

    // Bad operand, transform not used
    value = nzRandom()
    let badres = Result<Double>.error(TestError(value))
    let r3 = badres.map { (d: Double) throws -> Int in XCTFail(); return 0 }
    XCTAssert(TestError(value).matches(r3))
  }

  func testFlatMap()
  {
    var value = nzRandom()
    let goodres = Result.value(value)

    // Good operand, good transform
    let r1 = goodres.flatMap { Result.value(Int($0)*2) }
    XCTAssert(r1 == Result.value(Int(value)*2))

    // Good operand, transform errors
    let r2 = goodres.flatMap { Result<Double>.error(TestError($0)) }
    XCTAssert(TestError(value).matches(r2))

    // Bad operand, transform not used
    value = nzRandom()
    let badres = Result<Double>.error(TestError(value))
    let r3 = badres.flatMap { _ in Result<String> { XCTFail(); return "" } }
    XCTAssert(TestError(value).matches(r3))
  }

  func testRecover()
  {
    var value = nzRandom()
    let goodres = Result.value(value)

    // Good operand, transform short-circuited
    let r1 = goodres.recover { e in Result.value(value*2) }
    XCTAssert(r1 == Result.value(value))

    let badres = Result<Double>.error(TestError())

    // Bad operand, transform throws
    let r2 = badres.recover { e in Result.error(TestError(value)) }
    XCTAssert(TestError(value).matches(r2))

    // Bad operand, transform executes
    value = nzRandom()
    let r3 = badres.recover { e in Result.value(Double(value)) }
    XCTAssert(r3 == Result.value(Double(value)))
  }

  func testApplyA()
  {
    let value = Int(nzRandom() & 0x7fff + 10000)
    var error = nzRandom()

    // Good operand, good transform
    let o1 = Result.value(value)
    let t1 = Result.value { i throws in Double(value*i) }
    let r1 = o1.apply(t1)
    XCTAssert(r1 == Result.value(Double(value*value)))

    // Bad operand: transform not applied
    let o2 = Result<Int>.error(TestError(error))
    let t2 = Result.value({ (i:Int) throws -> Double in XCTFail(); return 0.0 })
    let r2 = o2.apply(t2)
    XCTAssert(TestError(error).matches(r2))

    // Good operand, transform Result carries error
    error = nzRandom()
    let o4 = Result.value(value)
    let t4 = Result.error(TestError(error)) as Result<(Int) throws -> UnsafeMutablePointer<AnyObject>>
    let r4 = o4.apply(t4)
    XCTAssert(TestError(error).matches(r4))
  }

  func testApplyB()
  {
    let value = Int(nzRandom() & 0x7fff + 10000)
    var error = nzRandom()

    // Good operand, good transform
    let o1 = Result.value(value)
    let t1 = Result.value { i in Result.value(Double(value*i)) }
    let r1 = o1.apply(t1)
    XCTAssert(r1 == Result.value(Double(value*value)))

    // Bad operand: transform not applied
    let o2 = Result<Int>.error(TestError(error))
    let t2 = Result.value { (i:Int) in Result<Double> { XCTFail(); return 0.0 } }
    let r2 = o2.apply(t2)
    XCTAssert(TestError(error).matches(r2))

    // Good operand, transform Result carries error
    error = nzRandom()
    let o4 = Result.value(value)
    let t4 = Result.error(TestError(error)) as Result<(Int) -> Result<UnsafeRawPointer>>
    let r4 = o4.apply(t4)
    XCTAssert(TestError(error).matches(r4))
  }

  func testQuestionMarkQuestionMarkOperator()
  {
    let r1 = Result.value(Int(nzRandom()))
    let v1 = r1 ?? -1
    XCTAssert(v1 > 0)

    let r2 = Result<Int>.error(TestError(nzRandom()))
    let v2 = r2 ?? -1
    XCTAssert(v2 < 0)
  }

  func testEquals()
  {
    let r1 = Result { 100-99 }
    XCTAssert(r1 == Result.value(1))

    let r2 = Result<Int> { throw TestError() }
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    XCTAssert(r2 == Result.error(TestError()))
#else
    // a poor substitute
    XCTAssert(TestError().matches(r2))
    XCTAssert(r2 != Result.error(TestError()))
#endif

    XCTAssert(r1 != r2)
  }

  func testEquals2()
  {
    let a1 = (0..<5).map { Result.value($0) }
    let a2 = (1...5).map { Result.value($0) }
    let a3 = a2.map { $0.map { $0 - 1 } }

    XCTAssert(a1 != a2)
    XCTAssert(a1 == a3)
    XCTAssert(a1 != [])
  }
}
