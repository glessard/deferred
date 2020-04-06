//
//  nzRandom.swift
//  deferred
//
//  Created by Guillaume Lessard on 2016-12-12.
//  Copyright © 2016-2020 Guillaume Lessard. All rights reserved.
//

func nzRandom() -> Int
{
  return Int.random(in: 1...0x1fff_ffff)
}
