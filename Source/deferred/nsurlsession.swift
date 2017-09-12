//
//  nsurlsession.swift
//  deferred
//
//  Created by Guillaume Lessard on 10/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

import Foundation
//import struct Foundation.Data
//import class  Foundation.FileHandle
//import struct Foundation.URL
//import struct Foundation.URLError
//import struct Foundation.URLRequest
//import class  Foundation.URLSession
//import class  Foundation.URLSessionTask
//import class  Foundation.URLSessionDownloadTask
//import let    Foundation.NSURLSessionDownloadTaskResumeData
//import class  Foundation.URLSessionUploadTask
//import class  Foundation.URLResponse
//import class  Foundation.HTTPURLResponse

public enum URLSessionError: Error
{
  case ServerStatus(Int)
  case InterruptedDownload(URLError, Data)
  case InvalidState
}

public class DeferredURLSessionTask<Value>: TBD<Value>
{
  private weak var task: URLSessionTask? = nil

  init(qos: DispatchQoS)
  {
    let queue = DispatchQueue(label: "urlsession", qos: qos, attributes: .concurrent)
    super.init(queue: queue)
  }

  @discardableResult
  override public func cancel(_ reason: String = "") -> Bool
  {
    guard !self.isDetermined, let task = task
    else { return super.cancel(reason) }

    // try to propagate the cancellation upstream
    task.cancel()
    // task.state == .canceling (checking would be nice, but that would require sleeping the thread)
    return true
  }

  public fileprivate(set) var urlSessionTask: URLSessionTask? {
    get {
      // is this thread-safe, or is a capture-and-return necessary?
      return task
    }
    set {
      task = newValue
    }
  }

  public override func enqueue(qos: DispatchQoS? = nil, task: @escaping (Determined<Value>) -> Void)
  {
    if state == .waiting
    {
      urlSessionTask?.resume()
      beginExecution()
    }
    super.enqueue(qos: qos, task: task)
  }
}

public extension URLSession
{
  private func dataCompletion(_ tbd: DeferredURLSessionTask<(Data, HTTPURLResponse)>) -> (Data?, URLResponse?, Error?) -> Void
  {
    return {
      (data: Data?, response: URLResponse?, error: Error?) in
      if let error = error
      {
        tbd.determine(error)
        return
      }

      if let d = data, let r = response as? HTTPURLResponse
      {
        tbd.determine( (d,r) )
        return
      }
      // Probably an impossible situation
      tbd.determine(URLSessionError.InvalidState)
    }
  }

  public func deferredDataTask(qos: DispatchQoS = DispatchQoS.current ?? .utility,
                               with request: URLRequest) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    let tbd = DeferredURLSessionTask<(Data, HTTPURLResponse)>(qos: qos)
    tbd.urlSessionTask = dataTask(with: request, completionHandler: dataCompletion(tbd))
    return tbd
  }

  public func deferredDataTask(qos: DispatchQoS = DispatchQoS.current ?? .utility,
                               with url: URL) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    return deferredDataTask(qos: qos, with: URLRequest(url: url))
  }
}

private class DeferredDownloadTask<Value>: DeferredURLSessionTask<Value>
{
  @discardableResult
  override func cancel(_ reason: String = "") -> Bool
  {
    guard !self.isDetermined,
          let task = urlSessionTask as? URLSessionDownloadTask
    else { return super.cancel(reason) }

    // try to propagate the cancellation upstream
    task.cancel(byProducingResumeData: { _ in }) // Let the completion handler collect the data for resuming.
    // task.state == .canceling (checking would be nice, but that would require sleeping the thread)
    return true
  }
}

extension URLSession
{
  private func downloadCompletion(_ tbd: DeferredURLSessionTask<(URL, FileHandle, HTTPURLResponse)>) -> (URL?, URLResponse?, Error?) -> Void
  {
    return {
      (url: URL?, response: URLResponse?, error: Error?) in
      if let error = error
      {
        if let error = error as? URLError, error.code == .cancelled
        {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
          let URLSessionDownloadTaskResumeData = NSURLSessionDownloadTaskResumeData
#endif
          if let data = error.userInfo[URLSessionDownloadTaskResumeData] as? Data
          { tbd.determine(URLSessionError.InterruptedDownload(error, data)) }
          else
          { tbd.determine(DeferredError.canceled(error.localizedDescription)) }
        }
        else
        { tbd.determine(error) }
        return
      }

      if let u = url, let r = response as? HTTPURLResponse
      {
        do {
          let f = try FileHandle(forReadingFrom: u)
          tbd.determine( (u,f,r) )
        }
        catch {
          // Likely an impossible situation
          tbd.determine(error)
        }
        return
      }
      // Probably an impossible situation
      tbd.determine(URLSessionError.InvalidState)
    }
  }

  public func deferredDownloadTask(qos: DispatchQoS = DispatchQoS.current ?? .utility,
                                   with request: URLRequest) -> DeferredURLSessionTask<(URL, FileHandle, HTTPURLResponse)>
  {
    let tbd = DeferredDownloadTask<(URL, FileHandle, HTTPURLResponse)>(qos: qos)
    tbd.urlSessionTask = downloadTask(with: request, completionHandler: downloadCompletion(tbd))
    return tbd
  }

  public func deferredDownloadTask(qos: DispatchQoS = DispatchQoS.current ?? .utility,
                                   with url: URL) -> DeferredURLSessionTask<(URL, FileHandle, HTTPURLResponse)>
  {
    return deferredDownloadTask(qos: qos, with: URLRequest(url: url))
  }

  public func deferredDownloadTask(qos: DispatchQoS = DispatchQoS.current ?? .utility,
                                   withResumeData data: Data) -> DeferredURLSessionTask<(URL, FileHandle, HTTPURLResponse)>
  {
    let tbd = DeferredDownloadTask<(URL, FileHandle, HTTPURLResponse)>(qos: qos)

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    tbd.urlSessionTask = downloadTask(withResumeData: data, completionHandler: downloadCompletion(tbd))
#else // swift-corelibs-foundation has the wrong signature for URLSession.downloadTask(withResumeData: …)
    tbd.cancel("URLSession.downloadTask(withResumeData: ) is not implemented in swift-corelibs-foundation")
#endif

    return tbd
  }
}

extension URLSession
{
  private func uploadCompletion(_ tbd: DeferredURLSessionTask<(Data, HTTPURLResponse)>) -> (Data?, URLResponse?, Error?) -> Void
  {
    return {
      (data: Data?, response: URLResponse?, error: Error?) in
      if let error = error
      {
        tbd.determine(error)
        return
      }

      if let d = data, let r = response as? HTTPURLResponse
      {
        tbd.determine( (d,r) )
        return
      }
      // Probably an impossible situation
      tbd.determine(URLSessionError.InvalidState)
    }
  }

  public func deferredUploadTask(qos: DispatchQoS = DispatchQoS.current ?? .utility,
                                 with request: URLRequest, fromData bodyData: Data) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    let tbd = DeferredURLSessionTask<(Data, HTTPURLResponse)>(qos: qos)
    tbd.urlSessionTask = uploadTask(with: request, from: bodyData, completionHandler: uploadCompletion(tbd))
    return tbd
  }

  public func deferredUploadTask(qos: DispatchQoS = DispatchQoS.current ?? .utility,
                                 with request: URLRequest, fromFile fileURL: URL) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    let tbd = DeferredURLSessionTask<(Data, HTTPURLResponse)>(qos: qos)
    tbd.urlSessionTask = uploadTask(with: request, fromFile: fileURL, completionHandler: uploadCompletion(tbd))
    return tbd
  }
}
