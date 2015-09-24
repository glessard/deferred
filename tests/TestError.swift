//
//  TestError.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-09-24.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

struct TestError: ErrorType, Equatable
{
  let error: UInt32
  init(_ e: UInt32) { error = e }
}

func == (l: TestError, r: TestError) -> Bool
{
  return l.error == r.error
}