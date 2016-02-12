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

extension NSURLSession
{
  private class DeferredDownloadTask: TBD<(NSURL, NSFileHandle, NSHTTPURLResponse)>
  {
    weak var task: NSURLSessionDownloadTask? = nil

    init() { super.init(queue: dispatch_get_global_queue(qos_class_self(), 0)) }

    override func cancel(reason: String) -> Bool
    {
      guard !self.isDetermined, let task = task else { return super.cancel(reason) }

      task.cancelByProducingResumeData {
        data in
        if let data = data
        { _ = try? self.determine(URLSessionError.InterruptedDownload(data)) }
      }
      return true
    }
  }

  public func deferredDownloadTask(request: NSURLRequest) -> Deferred<(NSURL, NSFileHandle, NSHTTPURLResponse)>
  {
    let tbd = DeferredDownloadTask()

    let task = self.downloadTaskWithRequest(request) {
      (url: NSURL?, response: NSURLResponse?, error: NSError?) in
      if let error = error
      { _ = try? tbd.determine(error) }
      else if let u = url, r = response as? NSHTTPURLResponse
      {
        let f = (try? NSFileHandle(forReadingFromURL: u)) ?? NSFileHandle.fileHandleWithNullDevice()
        _ = try? tbd.determine( (u,f,r) )
      }
      else
      { _ = try? tbd.determine(URLSessionError.InvalidState) }
    }

    tbd.task = task
    task.resume()
    tbd.beginExecution()
    return tbd
  }

  public func deferredDownloadTask(url: NSURL) -> Deferred<(NSURL, NSFileHandle, NSHTTPURLResponse)>
  {
    return deferredDownloadTask(NSURLRequest(URL: url))
  }

  public func deferredDownloadTask(data: NSData) -> Deferred<(NSURL, NSFileHandle, NSHTTPURLResponse)>
  {
    let tbd = DeferredDownloadTask()

    let task = self.downloadTaskWithResumeData(data) {
      (url: NSURL?, response: NSURLResponse?, error: NSError?) in
      if let error = error
      { _ = try? tbd.determine(error) }
      else if let u = url, r = response as? NSHTTPURLResponse
      {
        let f = (try? NSFileHandle(forReadingFromURL: u)) ?? NSFileHandle.fileHandleWithNullDevice()
        _ = try? tbd.determine( (u,f,r) )
      }
      else
      { _ = try? tbd.determine(URLSessionError.InvalidState) }
    }

    tbd.task = task
    task.resume()
    tbd.beginExecution()
    return tbd
  }
}
