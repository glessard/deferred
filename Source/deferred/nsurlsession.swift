//
//  nsurlsession.swift
//  deferred
//
//  Created by Guillaume Lessard on 10/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch
import Outcome

import Foundation

public enum URLSessionError: Error
{
  case ServerStatus(Int)
  case InterruptedDownload(URLError, Data)
  case InvalidState
}

public class DeferredURLSessionTask<Value>: Transferred<Value>
{
  public let urlSessionTask: URLSessionTask

  init(source: TBD<Value>, task: URLSessionTask)
  {
    urlSessionTask = task
    super.init(from: source, on: source.queue)
  }

  deinit {
    urlSessionTask.cancel()
  }

  @discardableResult
  public override func cancel(_ reason: String = "") -> Bool
  {
    guard !self.isDetermined else { return false }

    // try to propagate the cancellation upstream
    urlSessionTask.cancel()
    return true
  }

  public override func enqueue(queue: DispatchQueue? = nil, boostQoS: Bool = true,
                               task: @escaping (Outcome<Value>) -> Void)
  {
    if state == .waiting
    {
      beginExecution()
    }
    super.enqueue(queue: queue, boostQoS: boostQoS, task: task)
  }

  public override func beginExecution()
  {
    urlSessionTask.resume()
    super.beginExecution()
  }
}

extension URLSession
{
  private func dataCompletion(_ tbd: TBD<(Data, HTTPURLResponse)>) -> (Data?, URLResponse?, Error?) -> Void
  {
    return {
      [weak tbd] (data: Data?, response: URLResponse?, error: Error?) in
      guard let tbd = tbd else { return }

      if let error = error
      {
        tbd.determine(error: error)
        return
      }

      if let d = data, let r = response as? HTTPURLResponse
      {
        tbd.determine(value: (d,r))
      }
      else // Probably an impossible situation
      { tbd.determine(error: URLSessionError.InvalidState) }
    }
  }

  public func deferredDataTask(qos: DispatchQoS = .current,
                               with request: URLRequest) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    let tbd = TBD<(Data, HTTPURLResponse)>(qos: qos)

    let scheme = request.url?.scheme
    if scheme != "http" && scheme != "https"
    {
      let message = "deferred does not support url scheme \"\(scheme ?? "unknown")\""
      tbd.determine(error: DeferredError.invalid(message))
    }

    let task = dataTask(with: request, completionHandler: dataCompletion(tbd))
    return DeferredURLSessionTask(source: tbd, task: task)
  }

  public func deferredDataTask(qos: DispatchQoS = .current,
                               with url: URL) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    return deferredDataTask(qos: qos, with: URLRequest(url: url))
  }

  public func deferredUploadTask(qos: DispatchQoS = .current,
                                 with request: URLRequest, fromData bodyData: Data) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    let tbd = TBD<(Data, HTTPURLResponse)>(qos: qos)

    let scheme = request.url?.scheme
    if scheme != "http" && scheme != "https"
    {
      let message = "deferred does not support url scheme \"\(scheme ?? "unknown")\""
      tbd.determine(error: DeferredError.invalid(message))
    }

    let task = uploadTask(with: request, from: bodyData, completionHandler: dataCompletion(tbd))
    return DeferredURLSessionTask(source: tbd, task: task)
  }

  public func deferredUploadTask(qos: DispatchQoS = .current,
                                 with request: URLRequest, fromFile fileURL: URL) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    let tbd = TBD<(Data, HTTPURLResponse)>(qos: qos)

    let scheme = request.url?.scheme
    if scheme != "http" && scheme != "https"
    {
      let message = "deferred does not support url scheme \"\(scheme ?? "unknown")\""
      tbd.determine(error: DeferredError.invalid(message))
    }

    let task = uploadTask(with: request, fromFile: fileURL, completionHandler: dataCompletion(tbd))
    return DeferredURLSessionTask(source: tbd, task: task)
  }
}

private class DeferredDownloadTask<Value>: DeferredURLSessionTask<Value>
{
  init(source: TBD<Value>, task: URLSessionDownloadTask)
  {
    super.init(source: source, task: task)
  }

  @discardableResult
  override func cancel(_ reason: String = "") -> Bool
  {
    guard !self.isDetermined else { return false }

    let task = urlSessionTask as! URLSessionDownloadTask

#if os(Linux) && !swift(>=5.0)
    // swift-corelibs-foundation calls NSUnimplemented() as the body of cancel(byProducingResumeData:)
    task.cancel()
#else
    // try to propagate the cancellation upstream
    task.cancel(byProducingResumeData: { _ in }) // Let the completion handler collect the data for resuming.
#endif
    return true
  }
}

extension URLSession
{
  private func downloadCompletion(_ tbd: TBD<(URL, HTTPURLResponse)>) -> (URL?, URLResponse?, Error?) -> Void
  {
    return {
      [weak tbd] (location: URL?, response: URLResponse?, error: Error?) in
      guard let tbd = tbd else { return }

      if let error = error
      {
        if let error = error as? URLError
        {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
          // rdar://29623544 and https://bugs.swift.org/browse/SR-3403
          let URLSessionDownloadTaskResumeData = NSURLSessionDownloadTaskResumeData
#endif
          if let data = error.userInfo[URLSessionDownloadTaskResumeData] as? Data
          {
            tbd.determine(error: URLSessionError.InterruptedDownload(error, data))
            return
          }
        }

        tbd.determine(error: error)
        return
      }

#if os(Linux) && true
      print(location ?? "no url")
      print(response.map(String.init(describing:)) ?? "no response")
#endif

      if let response = response as? HTTPURLResponse
      {
        if let url = location
        { tbd.determine(value: (url, response)) }
        else
        { tbd.determine(error: URLSessionError.ServerStatus(response.statusCode)) } // should not happen
      }
      else // Probably an impossible situation
      { tbd.determine(error: URLSessionError.InvalidState) }
    }
  }

  public func deferredDownloadTask(qos: DispatchQoS = .current,
                                   with request: URLRequest) -> DeferredURLSessionTask<(URL, HTTPURLResponse)>
  {
    let tbd = TBD<(URL, HTTPURLResponse)>(qos: qos)

    let scheme = request.url?.scheme
    if scheme != "http" && scheme != "https"
    {
      let message = "deferred does not support url scheme \"\(scheme ?? "unknown")\""
      tbd.determine(error: DeferredError.invalid(message))
    }

    let task = downloadTask(with: request, completionHandler: downloadCompletion(tbd))
    return DeferredDownloadTask(source: tbd, task: task)
  }

  public func deferredDownloadTask(qos: DispatchQoS = .current,
                                   with url: URL) -> DeferredURLSessionTask<(URL, HTTPURLResponse)>
  {
    return deferredDownloadTask(qos: qos, with: URLRequest(url: url))
  }

  public func deferredDownloadTask(qos: DispatchQoS = .current,
                                   withResumeData data: Data) -> DeferredURLSessionTask<(URL, HTTPURLResponse)>
  {
    let tbd = TBD<(URL, HTTPURLResponse)>(qos: qos)

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    let task = downloadTask(withResumeData: data, completionHandler: downloadCompletion(tbd))
    return DeferredDownloadTask(source: tbd, task: task)
#else
    // swift-corelibs-foundation calls NSUnimplemented() as the body of downloadTask(withResumeData:)
    // It should instead call the completion handler with URLError.unsupportedURL
    // let task = downloadTask(withResumeData: data, completionHandler: downloadCompletion(tbd))
    let message = "The operation \'\(#function)\' is not supported on this platform"
    tbd.determine(error: URLError(.unsupportedURL, userInfo: [NSLocalizedDescriptionKey: message]))
    let task = downloadTask(with: URL(string: "invalid://data")!, completionHandler: { (_,_,_) in })
    return DeferredDownloadTask(source: tbd, task: task)
#endif
  }
}
