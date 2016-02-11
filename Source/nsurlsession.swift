//
//  nsurlsession.swift
//  deferred
//
//  Created by Guillaume Lessard on 10/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Foundation

public enum URLSessionError: ErrorType
{
  case ServerStatus(Int)
  case InterruptedDownload(NSData)
  case InvalidState
}

public extension NSURLSession
{
  private class DeferredDataTask: TBD<(NSData, NSHTTPURLResponse)>
  {
    weak var task: NSURLSessionDataTask? = nil

    init() { super.init(queue: dispatch_get_global_queue(qos_class_self(), 0)) }

    override func cancel(reason: String) -> Bool
    {
      guard !self.isDetermined, let task = task else { return super.cancel(reason) }

      // try to propagate the cancellation upstream
      task.cancel()
      return true
    }
  }

  public func deferredDataTask(request: NSURLRequest) -> Deferred<(NSData, NSHTTPURLResponse)>
  {
    let tbd = DeferredDataTask()

    let task = self.dataTaskWithRequest(request) {
      (data: NSData?, response: NSURLResponse?, error: NSError?) in
      if let error = error
      { _ = try? tbd.determine(error) }
      else if let d = data, r = response as? NSHTTPURLResponse
      { _ = try? tbd.determine( (d,r) ) }
      else
      { _ = try? tbd.determine(URLSessionError.InvalidState) }
    }

    tbd.task = task
    task.resume()
    tbd.beginExecution()
    return tbd
  }

  public func deferredDataTask(url: NSURL) -> Deferred<(NSData, NSHTTPURLResponse)>
  {
    return deferredDataTask(NSURLRequest(URL: url))
  }
}
