//
//  nzRandom.swift
//  deferred
//
//  Created by Guillaume Lessard on 12/12/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
  import func Darwin.arc4random
#else
  import func Glibc.random
#endif

func nzRandom() -> UInt32
{
  var r: UInt32
  repeat {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    r = arc4random() & 0x3fff_ffff
#else
    r = UInt32(random() & 0x3fff_ffff)
#endif
  } while (r == 0)

  return r
}
