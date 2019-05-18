//
//  nsurlsession.swift
//  deferred
//
//  Created by Guillaume Lessard on 10/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch
import Foundation

public enum URLSessionError: Error, Equatable
{
  case interruptedDownload(URLError, Data)
  case invalidState
}

public class DeferredURLSessionTask<Value>: TBD<Value>
{
  public private(set) weak var urlSessionTask: URLSessionTask? = nil

  init(qos: DispatchQoS = .current, error: Error)
  {
    super.init(qos: qos) { $0.resolve(error: error) }
  }

  init(qos: DispatchQoS = .current, task: (Resolver<Value>) -> URLSessionTask)
  {
    var resolver: Resolver<Value>!
    super.init(qos: qos, task: { resolver = $0 })
    let task = task(resolver)
    urlSessionTask = task
    resolver.retainSource(task)
  }

  deinit {
    if let state = urlSessionTask?.state
    { // only signal the task if necessary
      if state == .running || state == .suspended { urlSessionTask?.cancel() }
    }
  }

  @discardableResult
  public override func cancel(_ error: DeferredError) -> Bool
  {
    guard !self.isResolved, let task = urlSessionTask else { return false }

    let state = task.state
    guard state == .running || state == .suspended else { return false }

    // try to propagate the cancellation upstream
    task.cancel()
    return true
  }

  public override func notify(queue: DispatchQueue? = nil, boostQoS: Bool = true,
                              handler task: @escaping (Result<Value, Error>) -> Void)
  {
    if state == .waiting
    {
      beginExecution()
    }
    super.notify(queue: queue, boostQoS: boostQoS, handler: task)
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
        // note that response isn't necessarily `nil` here,
        // but does it ever contain anything that's not in the Error?
        resolver.resolve(error: error)
        return
      }

      if let r = response as? HTTPURLResponse
      {
        if let d = data
        { resolver.resolve(value: (d,r)) }
        else
        { resolver.resolve(error: URLSessionError.invalidState) }
      }
      else // Probably an impossible situation
      { resolver.resolve(error: URLSessionError.invalidState) }
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
  public override func cancel(_ error: DeferredError) -> Bool
  {
    guard !self.isResolved, let task = urlSessionTask as? URLSessionDownloadTask else { return false }

    let state = task.state
    guard state == .running || state == .suspended else { return false }

#if os(Linux) && !compiler(>=5.0)
    // swift-corelibs-foundation calls NSUnimplemented() as the body of cancel(byProducingResumeData:)
    task.cancel()
#else
    // try to propagate the cancellation upstream,
    // and let the other completion handler gather the resume data.
    task.cancel(byProducingResumeData: { _ in })
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

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
      // rdar://29623544 and https://bugs.swift.org/browse/SR-3403
      let URLSessionDownloadTaskResumeData = NSURLSessionDownloadTaskResumeData
#endif
      if let error = error as? URLError,
         let data = error.userInfo[URLSessionDownloadTaskResumeData] as? Data
      {
        resolver.resolve(error: URLSessionError.interruptedDownload(error, data))
        return
      }
      else if let error = error
      {
        // note that response isn't necessarily `nil` here,
        // but does it ever contain anything that's not in the Error?
        resolver.resolve(error: error)
        return
      }

#if os(Linux) && true
      print(location ?? "no url")
      print(response.map(String.init(describing:)) ?? "no response")
#endif

      if let response = response as? HTTPURLResponse
      {
        if let url = location
        { resolver.resolve(value: (url, response)) }
        else // should not happen
        { resolver.resolve(error: URLSessionError.invalidState) }
      }
      else // can happen if resume data is corrupted; otherwise probably an impossible situation
      { resolver.resolve(error: URLSessionError.invalidState) }
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
