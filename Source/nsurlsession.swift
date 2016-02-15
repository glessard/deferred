//
//  nsurlsession.swift
//  deferred
//
//  Created by Guillaume Lessard on 10/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Foundation
import Foundation.NSURLError

public enum URLSessionError: ErrorType
{
  case ServerStatus(Int)
  case InterruptedDownload(NSData)
  case InvalidState
}

public class DeferredURLSessionTask<T>: TBD<T>
{
  private weak var sessionTask: NSURLSessionTask? = nil

  init() { super.init(queue: dispatch_get_global_queue(qos_class_self(), 0)) }

  override public func cancel(reason: String = "") -> Bool
  {
    guard !self.isDetermined,
          let task = sessionTask
    else { return super.cancel(reason) }

    // try to propagate the cancellation upstream
    task.cancel()
    return task.state == .Canceling
  }

  public private(set) var task: NSURLSessionTask? {
    get {
      // is this thread-safe, or is a capture-and-return necessary?
      return sessionTask
    }
    set {
      sessionTask = newValue
    }
  }

  public override var result: Result<T> {
    self.task?.resume()
    self.beginExecution()
    return super.result
  }

  public override func notify(qos qos: qos_class_t, task: (Result<T>) -> Void)
  {
    self.task?.resume()
    self.beginExecution()
    super.notify(qos: qos, task: task)
  }
}

public extension NSURLSession
{
  private func dataCompletion(tbd: TBD<(NSData, NSHTTPURLResponse)>) -> (NSData?, NSURLResponse?, NSError?) -> Void
  {
    return {
      (data: NSData?, response: NSURLResponse?, error: NSError?) in
      if let error = error
      {
        _ = try? tbd.determine(error)
        return
      }

      if let d = data, r = response as? NSHTTPURLResponse
      {
        _ = try? tbd.determine( (d,r) )
        return
      }
      // Probably an impossible situation
      _ = try? tbd.determine(URLSessionError.InvalidState)
    }
  }

  public func deferredDataTask(request: NSURLRequest) -> DeferredURLSessionTask<(NSData, NSHTTPURLResponse)>
  {
    let tbd = DeferredURLSessionTask<(NSData, NSHTTPURLResponse)>()

    let task = self.dataTaskWithRequest(request, completionHandler: dataCompletion(tbd))

    tbd.task = task
    return tbd
  }

  public func deferredDataTask(url: NSURL) -> DeferredURLSessionTask<(NSData, NSHTTPURLResponse)>
  {
    return deferredDataTask(NSURLRequest(URL: url))
  }
}

private class DeferredDownloadTask<T>: DeferredURLSessionTask<T>
{
  override func cancel(reason: String = "") -> Bool
  {
    guard !self.isDetermined,
          let task = sessionTask as? NSURLSessionDownloadTask
    else { return super.cancel(reason) }

    // try to propagate the cancellation upstream
    task.cancelByProducingResumeData { _ in } // Let the completion handler collect the data for resuming.
    // task.state == .Canceling (checking would be nice, but that would require sleeping the thread)
    return true
  }
}

extension NSURLSession
{
  private func downloadCompletion(tbd: TBD<(NSURL, NSFileHandle, NSHTTPURLResponse)>) -> (NSURL?, NSURLResponse?, NSError?) -> Void
  {
    return {
      (url: NSURL?, response: NSURLResponse?, error: NSError?) in
      if let error = error
      {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled,
           let info = error.userInfo[NSURLSessionDownloadTaskResumeData],
           let data = info as? NSData
        { _ = try? tbd.determine(URLSessionError.InterruptedDownload(data)) }
        else
        { _ = try? tbd.determine(error) }
        return
      }

      if let u = url, r = response as? NSHTTPURLResponse
      {
        do {
          let f = try NSFileHandle(forReadingFromURL: u)
          _ = try? tbd.determine( (u,f,r) )
        }
        catch {
          // Likely an impossible situation
          _ = try? tbd.determine(error)
        }
        return
      }
      // Probably an impossible situation
      _ = try? tbd.determine(URLSessionError.InvalidState)
    }
  }

  public func deferredDownloadTask(request: NSURLRequest) -> DeferredURLSessionTask<(NSURL, NSFileHandle, NSHTTPURLResponse)>
  {
    let tbd = DeferredDownloadTask<(NSURL, NSFileHandle, NSHTTPURLResponse)>()

    let task = self.downloadTaskWithRequest(request, completionHandler: downloadCompletion(tbd))

    tbd.task = task
    return tbd
  }

  public func deferredDownloadTask(url: NSURL) -> DeferredURLSessionTask<(NSURL, NSFileHandle, NSHTTPURLResponse)>
  {
    return deferredDownloadTask(NSURLRequest(URL: url))
  }

  public func deferredDownloadTask(data: NSData) -> DeferredURLSessionTask<(NSURL, NSFileHandle, NSHTTPURLResponse)>
  {
    let tbd = DeferredDownloadTask<(NSURL, NSFileHandle, NSHTTPURLResponse)>()

    let task = self.downloadTaskWithResumeData(data, completionHandler: downloadCompletion(tbd))

    tbd.task = task
    return tbd
  }
}
