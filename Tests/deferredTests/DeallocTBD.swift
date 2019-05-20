//
//  File.swift
//  deferredTests
//
//  Created by Guillaume Lessard on 5/20/19.
//  Copyright © 2019 Guillaume Lessard. All rights reserved.
//

import XCTest
import deferred

class DeallocTBD<T>: TBD<T>
{
  let e: XCTestExpectation

  init(_ expectation: XCTestExpectation, task: (Resolver<T>) -> Void = { _ in })
  {
    e = expectation
    super.init(task: task)
  }

  deinit {
    e.fulfill()
  }
}
