//
//  atomics.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 23/11/2015.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Darwin


@inline(__always) func CAS<T>(current: UnsafeMutablePointer<T>?, new: UnsafeMutablePointer<T>?,
  target: UnsafeMutablePointer<UnsafeMutablePointer<T>?>) -> Bool
{
  return OSAtomicCompareAndSwapPtrBarrier(current, new, UnsafeMutablePointer(target))
}

@inline(__always) func CAS(current: Int32, new: Int32, target: UnsafeMutablePointer<Int32>) -> Bool
{
  return OSAtomicCompareAndSwap32Barrier(current, new, target)
}

@inline(__always) func syncread(_ p: UnsafeMutablePointer<Int32>) -> Int32
{
  return OSAtomicAdd32Barrier(0, p)
}
