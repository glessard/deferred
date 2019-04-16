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

public class DeferredURLSessionTask<Value>: TBD<Value>
{
  public fileprivate(set) var urlSessionTask: URLSessionTask?

  init(qos: DispatchQoS = .current, error: Error)
  {
    urlSessionTask = nil
    super.init(qos: qos) { $0.determine(error: error) }
  }

  init(qos: DispatchQoS = .current, execute: (Resolver<Value>) -> URLSessionTask)
  {
    var t: URLSessionTask?
    super.init(qos: qos, execute: { t = execute($0) })
    urlSessionTask = t.unsafelyUnwrapped
  }

  deinit {
    urlSessionTask?.cancel()
  }

  @discardableResult
  public override func cancel(_ reason: String = "") -> Bool
  {
    guard !self.isDetermined else { return false }

    // try to propagate the cancellation upstream
    urlSessionTask?.cancel()
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
    urlSessionTask?.resume()
    super.beginExecution()
  }
}

private func validateURL(_ request: URLRequest) throws
{
  let scheme = request.url?.scheme ?? "invalid"
  if scheme != "http" && scheme != "https"
  {
    let message = "deferred does not support url scheme \"\(scheme)\""
    throw DeferredError.invalid(message)
  }
}

extension URLSession
{
  private func dataCompletion(_ resolver: Resolver<(Data, HTTPURLResponse)>) -> (Data?, URLResponse?, Error?) -> Void
  {
    return {
      (data: Data?, response: URLResponse?, error: Error?) in

      if let error = error
      {
        resolver.determine(error: error)
        return
      }

      if let d = data, let r = response as? HTTPURLResponse
      {
        resolver.determine(value: (d,r))
      }
      else // Probably an impossible situation
      { resolver.determine(error: URLSessionError.InvalidState) }
    }
  }

  public func deferredDataTask(qos: DispatchQoS = .current,
                               with request: URLRequest) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    do { try validateURL(request) }
    catch {
      return DeferredURLSessionTask(qos: qos, error: error)
    }

    return DeferredURLSessionTask(qos: qos) {
      dataTask(with: request, completionHandler: dataCompletion($0))
    }
  }

  public func deferredDataTask(qos: DispatchQoS = .current,
                               with url: URL) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    return deferredDataTask(qos: qos, with: URLRequest(url: url))
  }

  public func deferredUploadTask(qos: DispatchQoS = .current,
                                 with request: URLRequest, fromData bodyData: Data) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    do { try validateURL(request) }
    catch {
      return DeferredURLSessionTask(qos: qos, error: error)
    }

    return DeferredURLSessionTask(qos: qos) {
      uploadTask(with: request, from: bodyData, completionHandler: dataCompletion($0))
    }
  }

  public func deferredUploadTask(qos: DispatchQoS = .current,
                                 with request: URLRequest, fromFile fileURL: URL) -> DeferredURLSessionTask<(Data, HTTPURLResponse)>
  {
    do { try validateURL(request) }
    catch {
      return DeferredURLSessionTask(qos: qos, error: error)
    }

    return DeferredURLSessionTask(qos: qos) {
      uploadTask(with: request, fromFile: fileURL, completionHandler: dataCompletion($0))
    }
  }
}

private class DeferredDownloadTask<Value>: DeferredURLSessionTask<Value>
{
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
  private func downloadCompletion(_ resolver: Resolver<(URL, HTTPURLResponse)>) -> (URL?, URLResponse?, Error?) -> Void
  {
    return {
      (location: URL?, response: URLResponse?, error: Error?) in

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
            resolver.determine(error: URLSessionError.InterruptedDownload(error, data))
            return
          }
        }

        resolver.determine(error: error)
        return
      }

#if os(Linux) && true
      print(location ?? "no url")
      print(response.map(String.init(describing:)) ?? "no response")
#endif

      if let response = response as? HTTPURLResponse
      {
        if let url = location
        { resolver.determine(value: (url, response)) }
        else
        { resolver.determine(error: URLSessionError.ServerStatus(response.statusCode)) } // should not happen
      }
      else // can happen if resume data is corrupted; otherwise probably an impossible situation
      { resolver.determine(error: URLSessionError.InvalidState) }
    }
  }

  public func deferredDownloadTask(qos: DispatchQoS = .current,
                                   with request: URLRequest) -> DeferredURLSessionTask<(URL, HTTPURLResponse)>
  {
    do { try validateURL(request) }
    catch {
      return DeferredURLSessionTask(qos: qos, error: error)
    }

    return DeferredDownloadTask(qos: qos) {
      downloadTask(with: request, completionHandler: downloadCompletion($0))
    }
  }

  public func deferredDownloadTask(qos: DispatchQoS = .current,
                                   with url: URL) -> DeferredURLSessionTask<(URL, HTTPURLResponse)>
  {
    return deferredDownloadTask(qos: qos, with: URLRequest(url: url))
  }

  public func deferredDownloadTask(qos: DispatchQoS = .current,
                                   withResumeData data: Data) -> DeferredURLSessionTask<(URL, HTTPURLResponse)>
  {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    return DeferredDownloadTask(qos: qos) {
      downloadTask(withResumeData: data, completionHandler: downloadCompletion($0))
    }
#else
    // swift-corelibs-foundation calls NSUnimplemented() as the body of downloadTask(withResumeData:)
    // It should instead call the completion handler with URLError.unsupportedURL
    // let task = downloadTask(withResumeData: data, completionHandler: downloadCompletion(tbd))
    let message = "The operation \'\(#function)\' is not supported on this platform"
    let error = URLError(.unsupportedURL, userInfo: [NSLocalizedDescriptionKey: message])
    return DeferredURLSessionTask(qos: qos, error: error)
#endif
  }
}
