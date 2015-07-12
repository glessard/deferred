//
//  main.swift
//  ExampleResultChain
//
//  Created by Guillaume Lessard on 2015-03-06.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Darwin

syncprint("Starting")
let sleeptime = 50_000

let result1 = async {
  _ -> Double in
  syncprint("Computing result1")
  usleep(numericCast(sleeptime))
  return 10.1
}

let result2 = result1.map {
  (d: Double) -> Int in
  syncprint("Computing result2")
  usleep(numericCast(sleeptime))
  return Int(floor(2*d))
}

let result3 = result1.map {
  (d: Double) -> String in
  syncprint("Computing result3")
  return (3*d).description
}

result3.notify { syncprint($0) }

let result4 = result3.combine(result2)

syncprint("Waiting")
syncprint(result1.value)
syncprint(result2.value)
syncprint(result3.value)
syncprint(result4.value)
syncprint("Done")
syncprintwait()
