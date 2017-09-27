//
//  TestError.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-09-24.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

struct TestError: Error, Equatable
{
  let error: Int
  init(_ e: Int = 0) { error = e }
}

func == (l: TestError, r: TestError) -> Bool
{
  return l.error == r.error
}
