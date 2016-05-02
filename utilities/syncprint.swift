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

private let PrintQueue = dispatch_queue_create("com.tffenterprises.syncprint", DISPATCH_QUEUE_SERIAL)
private let PrintGroup = dispatch_group_create()

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
  let thread = NSThread.current().isMainThread ? "[main]" : "[back]"

  dispatch_group_async(PrintGroup, PrintQueue) {
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
  let res = dispatch_group_wait(PrintGroup, dispatch_time(DISPATCH_TIME_NOW, 200_000_000))
  if res != 0
  {
    OSAtomicIncrement32Barrier(&silenceOutput)
    dispatch_group_notify(PrintGroup, PrintQueue) {
      print("Skipped output")
      OSAtomicDecrement32Barrier(&silenceOutput)
    }
  }
}
