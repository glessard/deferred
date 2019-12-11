import XCTest
import Foundation

class AlignmentTests: XCTestCase
{
  func testAlignmentOfPointerToSmallResult()
  {
    var p: UnsafeMutablePointer<Result<Void, Never>>
    XCTAssertEqual(MemoryLayout<Result<Void, Never>>.alignment, 1)

    p = UnsafeMutablePointer.allocate(capacity: 1)
    var pointers = [p]
    let mask = 0x03 as UInt
    for _ in 0..<1024
    {
      p = UnsafeMutablePointer.allocate(capacity: 1)
      pointers.append(p)

      let b = UInt(bitPattern: p)
      if b & mask != 0
      {
        XCTFail("tagged pointer is required: \(String(b & mask, radix: 16))")
      }
    }

    for p in pointers { p.deallocate() }
  }

  func testAlignmentOfRawPointer()
  {
    var pointers: [UnsafeMutableRawPointer] = []
    let mask = 0x03 as UInt
    for _ in 0..<1024
    {
      let p = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
      pointers.append(p)

      let b = UInt(bitPattern: p)
      if b & mask != 0
      {
        XCTFail("tagged pointer is required: \(String(b & mask, radix: 16))")
      }
    }

    for p in pointers { p.deallocate() }
  }
}
