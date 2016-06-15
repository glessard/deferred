//
//  syncprint.swift
//
//  Created by Guillaume Lessard on 2014-08-22.
//  Copyright (c) 2014, 2015 Guillaume Lessard. All rights reserved.
//
//  https://gist.github.com/glessard/826241431dcea3655d1e
//

import Dispatch
import Foundation.NSThread

private let PrintQueue = DispatchQueue(label: "com.tffenterprises.syncprint", attributes: .serial)
private let PrintGroup = DispatchGroup()

private var silenceOutput: Int32 = 0

///  A wrapper for `Swift.print()` that executes all requests on a serial queue.
///  Useful for logging from multiple threads.
///
///  Writes a basic thread identifier (main or back), the textual representation
///  of `item`, and a newline character onto the standard output.
///
///  The textual representation is from the `String` initializer, `String(item)`
///
///  - parameter item: the item to be printed

public func syncprint(_ item: Any)
{
  let thread = Thread.current().isMainThread ? "[main]" : "[back]"

  PrintQueue.async(group: PrintGroup) {
    // Read silenceOutput atomically
    if OSAtomicAdd32(0, &silenceOutput) == 0
    {
      print(thread, item, separator: " ")
    }
  }
}

///  Block until all tasks created by syncprint() have completed.

public func syncprintwait()
{
  // Wait at most 200ms for the last messages to print out.
  let res = PrintGroup.wait(timeout: DispatchTime.now() + Double(200_000_000) / Double(NSEC_PER_SEC))
  if res == .TimedOut
  {
    OSAtomicIncrement32Barrier(&silenceOutput)
    PrintGroup.notify(queue: PrintQueue) {
      print("Skipped output")
      OSAtomicDecrement32Barrier(&silenceOutput)
    }
  }
}
