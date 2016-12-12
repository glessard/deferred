//
//  atomics.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 23/11/2015.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

#if !SWIFT_PACKAGE

import ClangAtomics

internal enum CASType
{
  case strong, weak
}

internal enum MemoryOrder: Int
{
  case relaxed = 0, consume, acquire, release, acqrel, sequential

  var order: memory_order {
    switch self {
    case .relaxed:    return memory_order_relaxed
    case .consume:    return memory_order_consume
    case .acquire:    return memory_order_acquire
    case .release:    return memory_order_release
    case .acqrel:     return memory_order_acq_rel
    case .sequential: return memory_order_seq_cst
    }
  }
}

internal enum LoadMemoryOrder: Int
{
  case relaxed = 0, consume, acquire, sequential = 5

  var order: memory_order {
    switch self {
    case .relaxed:    return memory_order_relaxed
    case .consume:    return memory_order_consume
    case .acquire:    return memory_order_acquire
    case .sequential: return memory_order_seq_cst
    }
  }
}

internal enum StoreMemoryOrder: Int
{
  case relaxed = 0, release = 3, sequential = 5

  var order: memory_order {
    switch self {
    case .relaxed:    return memory_order_relaxed
    case .release:    return memory_order_release
    case .sequential: return memory_order_seq_cst
    }
  }
}

internal struct AtomicMutablePointer<Pointee>
{
  fileprivate var ptr: UnsafeMutableRawPointer?
  internal init(_ ptr: UnsafeMutablePointer<Pointee>? = nil) { self.ptr = UnsafeMutableRawPointer(ptr) }

  internal var pointer: UnsafeMutablePointer<Pointee>? {
    mutating get {
      return ReadRawPtr(&ptr, memory_order_relaxed)?.assumingMemoryBound(to: Pointee.self)
    }
  }

  @inline(__always)
  internal mutating func load(order: LoadMemoryOrder = .sequential) -> UnsafeMutablePointer<Pointee>?
  {
    return ReadRawPtr(&ptr, order.order)?.assumingMemoryBound(to: Pointee.self)
  }

  @inline(__always)
  internal mutating func swap(_ pointer: UnsafeMutablePointer<Pointee>?, order: MemoryOrder = .sequential) -> UnsafeMutablePointer<Pointee>?
  {
    return SwapRawPtr(UnsafePointer(pointer), &ptr, order.order)?.assumingMemoryBound(to: (Pointee).self)
  }

  @inline(__always) @discardableResult
  internal mutating func CAS(current: UnsafeMutablePointer<Pointee>?, future: UnsafeMutablePointer<Pointee>?,
                             type: CASType = .weak,
                             orderSuccess: MemoryOrder = .sequential,
                             orderFailure: LoadMemoryOrder = .sequential) -> Bool
  {
    precondition(orderFailure.rawValue <= orderSuccess.rawValue)
    var expect = UnsafeMutableRawPointer(current)
    return CASWeakRawPtr(&expect, UnsafePointer(future), &ptr, orderSuccess.order, orderFailure.order)
  }
}

internal struct AtomicInt32
{
  fileprivate var val: Int32 = 0
  internal init(_ v: Int32 = 0) { val = v }

  internal var value: Int32 {
    mutating get { return Read32(&val, memory_order_relaxed) }
  }

  @inline(__always)
  internal mutating func store(_ value: Int32, order: StoreMemoryOrder = .relaxed)
  {
    Store32(value, &val, order.order)
  }
}

#endif
