//
//  atomics.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 23/11/2015.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

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

@inline(__always) @discardableResult
func CAS(current: Int32, new: Int32, target: UnsafeMutablePointer<Int32>) -> Bool
{
  return OSAtomicCompareAndSwap32Barrier(current, new, target)
}

@inline(__always) func syncread(_ p: UnsafeMutablePointer<Int32>) -> Int32
{
  return OSAtomicAdd32Barrier(0, p)
}
