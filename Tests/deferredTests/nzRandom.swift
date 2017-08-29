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

func nzRandom() -> Int
{
  var r: Int
  repeat {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    r = Int(arc4random() & 0x1fff_ffff)
#else
    r = random() & 0x1fff_ffff
#endif
  } while (r == 0)

  return r
}
