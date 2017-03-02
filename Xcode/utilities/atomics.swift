//
//  atomics.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 23/11/2015.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

#if !SWIFT_PACKAGE

import ClangAtomics

enum CASType
{
  case strong, weak
}

enum MemoryOrder: Int
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

enum LoadMemoryOrder: Int
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

enum StoreMemoryOrder: Int
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

struct AtomicMutablePointer<Pointee>
{
  @_versioned var ptr = RawPointer()
  init(_ p: UnsafeMutablePointer<Pointee>? = nil)
  {
    InitRawPtr(UnsafeRawPointer(p), &ptr)
  }

  @inline(__always)
  mutating func load(order: LoadMemoryOrder = .sequential) -> UnsafeMutablePointer<Pointee>?
  {
    return ReadRawPtr(&ptr, order.order)?.assumingMemoryBound(to: Pointee.self)
  }

  @inline(__always) @discardableResult
  mutating func swap(_ pointer: UnsafeMutablePointer<Pointee>?, order: MemoryOrder = .sequential) -> UnsafeMutablePointer<Pointee>?
  {
    return SwapRawPtr(pointer, &ptr, order.order)?.assumingMemoryBound(to: (Pointee).self)
  }

  @inline(__always) @discardableResult
  mutating func loadCAS(current: UnsafeMutablePointer<UnsafeMutablePointer<Pointee>?>,
                        future: UnsafeMutablePointer<Pointee>?,
                        type: CASType = .weak, // ignored
                        orderSwap: MemoryOrder = .sequential,
                        orderLoad: LoadMemoryOrder = .sequential) -> Bool
  {
    assert(orderLoad.rawValue <= orderSwap.rawValue)
    assert(orderSwap == .release ? orderLoad == .relaxed : true)
    return current.withMemoryRebound(to: Optional<UnsafeRawPointer>.self, capacity: 1) {
      current in
      WeakCASRawPtr(current, future, &ptr, orderSwap.order, orderLoad.order)
    }
  }
}

struct AtomicInt32
{
  @_versioned var val = Atomic32()
  init(_ value: Int32 = 0)
  {
    Init32(value, &val)
  }

  @inline(__always)
  mutating func load(order: LoadMemoryOrder = .relaxed) -> Int32
  {
    return Read32(&val, order.order)
  }

  @inline(__always)
  mutating func store(_ value: Int32, order: StoreMemoryOrder = .relaxed)
  {
    Store32(value, &val, order.order)
  }

  @inline(__always) @discardableResult
  mutating func loadCAS(current: UnsafeMutablePointer<Int32>, future: Int32,
                        type: CASType = .weak, // ignored
                        orderSwap: MemoryOrder = .relaxed,
                        orderLoad: LoadMemoryOrder = .relaxed) -> Bool
  {
    assert(orderLoad.rawValue <= orderSwap.rawValue)
    assert(orderSwap == .release ? orderLoad == .relaxed : true)
    return WeakCAS32(current, future, &val, orderSwap.order, orderLoad.order)
  }

  @inline(__always) @discardableResult
  mutating func CAS(current: Int32, future: Int32,
                    type: CASType = .weak, // ignored
                    order: MemoryOrder = .relaxed) -> Bool
  {
    var expect = current
    return loadCAS(current: &expect, future: future, type: type, orderSwap: order, orderLoad: .relaxed)
  }
}

#endif
