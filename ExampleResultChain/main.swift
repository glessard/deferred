//
//  main.swift
//  ExampleResultChain
//
//  Created by Guillaume Lessard on 2015-03-06.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Darwin

syncprint("Starting")

let result1 = async {
  _ -> Double in
  syncprint("Starting result1")
  sleep(1)
  syncprint("Finishing result1")
  return 10.1
}

let result2 = result1.notify {
  (d: Double) -> Int in
  syncprint("Starting result2")
  sleep(1)
  syncprint("Finishing result2")
  return Int(floor(2*d))
}

let result3 = result1.notify { return (3*$0).description }

result3.notify { syncprint($0) }

syncprint("Waiting")
syncprint(result1.value)
syncprint(result2.value)
syncprint(result3.value)
syncprint("Done")
syncprintwait()
