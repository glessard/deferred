//
//  atomics.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 23/11/2015.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

#if !SWIFT_PACKAGE

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

func CAS<T>(current: UnsafeMutablePointer<T>?, new: UnsafeMutablePointer<T>?,
            target: UnsafeMutablePointer<UnsafeMutablePointer<T>?>) -> Bool
{
  if target.pointee == current
  {
    target.pointee = new
    return true
  }
  return false
}

func syncread<T>(_ p: UnsafeMutablePointer<UnsafeMutablePointer<T>?>) -> UnsafeMutablePointer<T>?
{
  return p.pointee
}

func swap<T>(value: UnsafeMutablePointer<T>?,
             target: UnsafeMutablePointer<UnsafeMutablePointer<T>?>) -> UnsafeMutablePointer<T>?
{
  let cur = target.pointee
  target.pointee = value
  return cur
}

func syncread(_ p: UnsafeMutablePointer<Int32>) -> Int32
{
  return p.pointee
}

#endif
