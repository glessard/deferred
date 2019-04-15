//
//  nzRandom.swift
//  deferred
//
//  Created by Guillaume Lessard on 12/12/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

func nzRandom() -> Int
{
  return Int.random(in: 1...0x1fff_ffff)
}
