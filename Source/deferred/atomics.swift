//
//  atomics.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 23/11/2015.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

#if false // !SWIFT_PACKAGE

import func Darwin.OSAtomicCompareAndSwapPtrBarrier
import func Darwin.OSAtomicCompareAndSwap32Barrier
import func Darwin.OSAtomicAdd32Barrier

@inline(__always) @discardableResult
func CAS<T>(current: UnsafeMutablePointer<T>?, new: UnsafeMutablePointer<T>?,
            target: UnsafeMutablePointer<UnsafeMutablePointer<T>?>) -> Bool
{
  return target.withMemoryRebound(to: (UnsafeMutableRawPointer?).self, capacity: 1) {
    OSAtomicCompareAndSwapPtrBarrier(current, new, $0)
  }
}

@inline(__always)
func syncread<T>(_ p: UnsafeMutablePointer<UnsafeMutablePointer<T>?>) -> UnsafeMutablePointer<T>?
{
  while true
  {
    let pointer = p.pointee
    if CAS(current: pointer, new: pointer, target: p)
    {
      return pointer
    }
  }
}

@inline(__always)
func swap<T>(value: UnsafeMutablePointer<T>?,
             target: UnsafeMutablePointer<UnsafeMutablePointer<T>?>) -> UnsafeMutablePointer<T>?
{
  while true
  { // a tortured implementation for an atomic swap
    let current = target.pointee
    if CAS(current: current, new: value, target: target)
    {
      return current
    }
  }
}

@inline(__always)
func syncread(_ p: UnsafeMutablePointer<Int32>) -> Int32
{
  return OSAtomicAdd32Barrier(0, p)
}

#else

import ClangAtomics

public struct AtomicMutablePointer<Pointee>
{
  fileprivate var ptr: UnsafeMutableRawPointer?
  public init(_ ptr: UnsafeMutablePointer<Pointee>? = nil) { self.ptr = UnsafeMutableRawPointer(ptr) }

  public var pointer: UnsafeMutablePointer<Pointee>? {
    mutating get {
      return ReadRawPtr(&ptr, memory_order_relaxed)?.assumingMemoryBound(to: Pointee.self)
    }
  }

  @inline(__always)
  public mutating func load(order: LoadMemoryOrder = .sequential) -> UnsafeMutablePointer<Pointee>?
  {
    return ReadRawPtr(&ptr, order.order)?.assumingMemoryBound(to: Pointee.self)
  }

  @inline(__always)
  public mutating func swap(_ pointer: UnsafeMutablePointer<Pointee>?, order: MemoryOrder = .sequential) -> UnsafeMutablePointer<Pointee>?
  {
    return SwapRawPtr(UnsafePointer(pointer), &ptr, order.order)?.assumingMemoryBound(to: (Pointee).self)
  }

  @inline(__always) @discardableResult
  public mutating func CAS(current: UnsafeMutablePointer<Pointee>?, future: UnsafeMutablePointer<Pointee>?,
                           orderSuccess: MemoryOrder = .sequential,
                           orderFailure: LoadMemoryOrder = .sequential) -> Bool
  {
    precondition(orderFailure.rawValue <= orderSuccess.rawValue)
    var expect = UnsafeMutableRawPointer(current)
    return CASWeakRawPtr(&expect, UnsafePointer(future), &ptr, orderSuccess.order, orderFailure.order)
  }
}

public struct AtomicInt32
{
  fileprivate var val: Int32 = 0
  public init(_ v: Int32 = 0) { val = v }

  public var value: Int32 {
    mutating get { return Read32(&val, memory_order_relaxed) }
  }

  @inline(__always)
  public mutating func store(_ value: Int32, order: StoreMemoryOrder = .relaxed)
  {
    Store32(value, &val, order.order)
  }
}

#endif
