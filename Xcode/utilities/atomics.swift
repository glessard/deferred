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
  case relaxed = 0, /* consume, */ acquire = 2, release, acqrel, sequential

  var order: memory_order {
    switch self {
    case .relaxed:    return memory_order_relaxed
    // case .consume:    return memory_order_consume
    case .acquire:    return memory_order_acquire
    case .release:    return memory_order_release
    case .acqrel:     return memory_order_acq_rel
    case .sequential: return memory_order_seq_cst
    }
  }
}

internal enum LoadMemoryOrder: Int
{
  case relaxed = 0, /* consume, */ acquire = 2, sequential = 5

  var order: memory_order {
    switch self {
    case .relaxed:    return memory_order_relaxed
    // case .consume:    return memory_order_consume
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
  fileprivate var ptr = RawPointer()
  internal init(_ p: UnsafeMutablePointer<Pointee>? = nil)
  {
    StoreRawPtr(UnsafeRawPointer(p), &ptr, memory_order_relaxed)
  }

  @inline(__always)
  internal mutating func load(order: LoadMemoryOrder = .sequential) -> UnsafeMutablePointer<Pointee>?
  {
    return ReadRawPtr(&ptr, order.order)?.assumingMemoryBound(to: Pointee.self)
  }

  @inline(__always)
  internal mutating func swap(_ pointer: UnsafeMutablePointer<Pointee>?, order: MemoryOrder = .sequential) -> UnsafeMutablePointer<Pointee>?
  {
    return SwapRawPtr(pointer, &ptr, order.order)?.assumingMemoryBound(to: (Pointee).self)
  }

  @inline(__always) @discardableResult
  public mutating func loadCAS(current: UnsafeMutablePointer<UnsafeMutablePointer<Pointee>?>,
                               future: UnsafeMutablePointer<Pointee>?,
                               type: CASType = .weak, // ignored
                               orderSwap: MemoryOrder = .sequential,
                               orderLoad: LoadMemoryOrder = .sequential) -> Bool
  {
    assert(orderLoad.rawValue <= orderSwap.rawValue)
    return current.withMemoryRebound(to: Optional<UnsafeRawPointer>.self, capacity: 1) {
      current in
      WeakCASRawPtr(current, future, &ptr, orderSwap.order, orderLoad.order)
    }
  }
}

internal struct AtomicInt32
{
  fileprivate var val = Atomic32()
  internal init(_ value: Int32 = 0)
  {
    Store32(value, &val, memory_order_relaxed)
  }

  @inline(__always)
  internal mutating func load(order: LoadMemoryOrder = .relaxed) -> Int32
  {
    return Read32(&val, order.order)
  }

  @inline(__always)
  internal mutating func store(_ value: Int32, order: StoreMemoryOrder = .relaxed)
  {
    Store32(value, &val, order.order)
  }
}

#endif
