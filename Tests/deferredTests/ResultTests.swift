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
  static var allTests: [(String, (ResultTests) -> () throws -> Void)] {
    return [
      ("testInitValue", testInitValue),
      ("testInitError", testInitError),
      ("testInitClosureSuccess", testInitClosureSuccess),
      ("testInitClosureError", testInitClosureError),
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
  }

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

  func testInitClosureSuccess()
  {
    let val = nzRandom()
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
    let err = TestError(nzRandom())
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
    let value = nzRandom()
    let goodres = Result.value(value)

    // Good operand, good transform
    let r1 = goodres.map { Int($0)*2 }
    XCTAssert(r1 == Result.value(Int(value)*2))

    // Good operand, transform throws
    let r2 = goodres.map { (i:UInt32) throws -> Double in throw TestError(i) }
    XCTAssert(r2 == Result.error(TestError(value)))

    let badres = Result<Double>.error(TestError(value))

    // Bad operand, transform not used
    let r3 = badres.map { (d: Double) throws -> Int in XCTFail(); return 0 }
    XCTAssert(r3 == Result.error(TestError(value)))
  }

  func testFlatMap()
  {
    let value = nzRandom()
    let goodres = Result.value(value)

    // Good operand, good transform
    let r1 = goodres.flatMap { Result.value(Int($0)*2) }
    XCTAssert(r1 == Result.value(Int(value)*2))

    // Good operand, transform errors
    let r2 = goodres.flatMap { Result<Double>.error(TestError($0)) }
    XCTAssert(r2 == Result.error(TestError(value)))

    let badres = Result<Double>.error(TestError(value))

    // Bad operand, transform not used
    let r3 = badres.flatMap { _ in Result<String> { XCTFail(); return "" } }
    XCTAssert(r3 == Result.error(TestError(value)))
  }

  func testRecover()
  {
    let value = nzRandom()
    let goodres = Result.value(value)

    // Good operand, transform short-circuited
    let r1 = goodres.recover { e in Result.value(value*2) }
    XCTAssert(r1 == Result.value(value))

    let badres = Result<Double>.error(TestError())

    // Bad operand, transform throws
    let r2 = badres.recover { e in Result.error(TestError(value)) }
    XCTAssert(r2 == Result.error(TestError(value)))

    // Bad operand, transform executes
    let r3 = badres.recover { e in Result.value(Double(value)) }
    XCTAssert(r3 == Result.value(Double(value)))
  }

  func testApplyA()
  {
    let value = Int(nzRandom() & 0x7fff + 10000)
    let error = nzRandom()

    // Good operand, good transform
    let o1 = Result.value(value)
    let t1 = Result.value { i throws in Double(value*i) }
    let r1 = o1.apply(t1)
    XCTAssert(r1 == Result.value(Double(value*value)))

    // Bad operand: transform not applied
    let o2 = Result<Int>.error(TestError(error))
    let t2 = Result.value({ (i:Int) throws -> Double in XCTFail(); return 0.0 })
    let r2 = o2.apply(t2)
    XCTAssert(r2 == Result.error(TestError(error)))

    // Good operand, transform Result carries error
    let o4 = Result.value(value)
    let t4 = Result.error(TestError(error)) as Result<(Int) throws -> UnsafeMutablePointer<AnyObject>>
    let r4 = o4.apply(t4)
    XCTAssert(r4 == Result.error(TestError(error)))
  }

  func testApplyB()
  {
    let value = Int(nzRandom() & 0x7fff + 10000)
    let error = nzRandom()

    // Good operand, good transform
    let o1 = Result.value(value)
    let t1 = Result.value { i in Result.value(Double(value*i)) }
    let r1 = o1.apply(t1)
    XCTAssert(r1 == Result.value(Double(value*value)))

    // Bad operand: transform not applied
    let o2 = Result<Int>.error(TestError(error))
    let t2 = Result.value { (i:Int) in Result<Double> { XCTFail(); return 0.0 } }
    let r2 = o2.apply(t2)
    XCTAssert(r2 == Result.error(TestError(error)))

    // Good operand, transform Result carries error
    let o4 = Result.value(value)
    let t4 = Result.error(TestError(error)) as Result<(Int) -> Result<UnsafeRawPointer>>
    let r4 = o4.apply(t4)
    XCTAssert(r4 == Result.error(TestError(error)))
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
    XCTAssert(r2 == Result.error(TestError()))

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