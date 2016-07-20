//
//  nsurlsession.swift
//  deferred
//
//  Created by Guillaume Lessard on 10/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Foundation

public enum URLSessionError: ErrorProtocol
{
  case ServerStatus(Int)
  case InterruptedDownload(Data)
  case InvalidState
}

public class DeferredURLSessionTask<Value>: TBD<Value>
{
  private weak var sessionTask: URLSessionTask? = nil

  init() { super.init(queue: DispatchQueue.global()) }

  override public func cancel(_ reason: String = "") -> Bool
  {
    guard !self.isDetermined,
          let task = sessionTask
    else { return super.cancel(reason) }

    // try to propagate the cancellation upstream
    task.cancel()
    return task.state == .canceling
  }

  public private(set) var task: URLSessionTask? {
    get {
      // is this thread-safe, or is a capture-and-return necessary?
      return sessionTask
    }
    set {
      sessionTask = newValue
    }
  }

  public override var result: Result<Value> {
    self.task?.resume()
    self.beginExecution()
    return super.result
  }

  public override func notify(qos: DispatchQoS = .unspecified, task: (Result<Value>) -> Void)
  {
    self.task?.resume()
    self.beginExecution()
    super.notify(qos: qos, task: task)
  }
}

public extension URLSession
{
  private func dataCompletion(_ tbd: DeferredURLSessionTask<(Data, HTTPURLResponse)>) -> (Data?, URLResponse?, NSError?) -> Void
  {
    return {
      (data: Data?, response: URLResponse?, error: NSError?) in
      if let error = error
      {
        _ = try? tbd.determine(error)
        return
      }

      if let d = data, let r = response as? HTTPURLResponse
      {
        _ = try? tbd.determine( (d,r) )
        return
      }
      // Probably an impossible situation
      _ = try? tbd.determine(URLSessionError.InvalidState)
    }
  }

  public func deferredDataTask(with request: URLRequest) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    let tbd = DeferredURLSessionTask<(Data, HTTPURLResponse)>()

    let task = self.dataTask(with: request, completionHandler: dataCompletion(tbd))

    tbd.task = task
    return tbd
  }

  public func deferredDataTask(with url: URL) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    return deferredDataTask(with: URLRequest(url: url))
  }
}

private class DeferredDownloadTask<Value>: DeferredURLSessionTask<Value>
{
  override func cancel(_ reason: String = "") -> Bool
  {
    guard !self.isDetermined,
          let task = sessionTask as? URLSessionDownloadTask
    else { return super.cancel(reason) }

    // try to propagate the cancellation upstream
    task.cancel(byProducingResumeData: { _ in }) // Let the completion handler collect the data for resuming.
    // task.state == .canceling (checking would be nice, but that would require sleeping the thread)
    return true
  }
}

extension URLSession
{
  private func downloadCompletion(_ tbd: DeferredURLSessionTask<(URL, FileHandle, HTTPURLResponse)>) -> (URL?, URLResponse?, NSError?) -> Void
  {
    return {
      (url: URL?, response: URLResponse?, error: NSError?) in
      if let error = error
      {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled,
           let data = error.userInfo[NSURLSessionDownloadTaskResumeData as NSString] as? Data
        { _ = try? tbd.determine(URLSessionError.InterruptedDownload(data)) }
        else
        { _ = try? tbd.determine(error) }
        return
      }

      if let u = url, let r = response as? HTTPURLResponse
      {
        do {
          let f = try FileHandle(forReadingFrom: u)
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

  public func deferredDownloadTask(with request: URLRequest) -> DeferredURLSessionTask<(URL, FileHandle, HTTPURLResponse)>
  {
    let tbd = DeferredDownloadTask<(URL, FileHandle, HTTPURLResponse)>()

    let task = self.downloadTask(with: request, completionHandler: downloadCompletion(tbd))

    tbd.task = task
    return tbd
  }

  public func deferredDownloadTask(with url: URL) -> DeferredURLSessionTask<(URL, FileHandle, HTTPURLResponse)>
  {
    return deferredDownloadTask(with: URLRequest(url: url))
  }

  public func deferredDownloadTask(resumeData data: Data) -> DeferredURLSessionTask<(URL, FileHandle, HTTPURLResponse)>
  {
    let tbd = DeferredDownloadTask<(URL, FileHandle, HTTPURLResponse)>()

    let task = self.downloadTask(withResumeData: data, completionHandler: downloadCompletion(tbd))

    tbd.task = task
    return tbd
  }
}

extension URLSession
{
  private func uploadCompletion(_ tbd: DeferredURLSessionTask<(Data, HTTPURLResponse)>) -> (Data?, URLResponse?, NSError?) -> Void
  {
    return {
      (data: Data?, response: URLResponse?, error: NSError?) in
      if let error = error
      {
        _ = try? tbd.determine(error)
        return
      }

      if let d = data, let r = response as? HTTPURLResponse
      {
        _ = try? tbd.determine( (d,r) )
        return
      }
      // Probably an impossible situation
      _ = try? tbd.determine(URLSessionError.InvalidState)
    }
  }

  public func deferredUploadTask(request: URLRequest, fromData bodyData: Data) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    let tbd = DeferredURLSessionTask<(Data, HTTPURLResponse)>()

    let task = self.uploadTask(with: request, from: bodyData, completionHandler: uploadCompletion(tbd))

    tbd.task = task
    return tbd
  }

  public func deferredUploadTask(request: URLRequest, fromFile fileURL: URL) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    let tbd = DeferredURLSessionTask<(Data, HTTPURLResponse)>()

    let task = self.uploadTask(with: request, fromFile: fileURL, completionHandler: uploadCompletion(tbd))

    tbd.task = task
    return tbd
  }
}
