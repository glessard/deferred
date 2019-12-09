//
//  CallbackTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 09/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import deferred

let baseURL = URL(string: "http://www.somewhere.com/")!
let unavailableURL = URL(string: "http://127.0.0.1:65521/image.jpg")!

public class TestURLServer: URLProtocol
{
  typealias Response = (URLRequest) -> ([Command], HTTPURLResponse)
  static private var testURLs: [URL: Response] = [:]

  public enum Command
  {
    case load(Data), wait(TimeInterval), fail(Error), finishLoading
  }

  static func register(url: URL, response: @escaping Response)
  {
    testURLs[url] = response
  }

  public override class func canInit(with request: URLRequest) -> Bool
  {
    return true
  }

  public override class func canonicalRequest(for request: URLRequest) -> URLRequest
  {
    return request
  }

  private func dispatchNextCommand<Commands>(queue: DispatchQueue, chunks: Commands)
    where Commands: Collection, Commands.Element == Command
  {
    if #available(iOS 10, macOS 10.12, tvOS 10, watchOS 3, *)
    {
      dispatchPrecondition(condition: .onQueue(queue))
    }

    switch chunks.first ?? .finishLoading
    {
    case .load(let data):
      client?.urlProtocol(self, didLoad: data)
      queue.async {
        [chunks = chunks.dropFirst()] in
        self.dispatchNextCommand(queue: queue, chunks: chunks)
      }
    case .wait(let interval):
      queue.asyncAfter(deadline: .now() + interval) {
        [chunks = chunks.dropFirst()] in
        self.dispatchNextCommand(queue: queue, chunks: chunks)
      }
    case .fail(let error):
      client?.urlProtocol(self, didFailWithError: error)
    case .finishLoading:
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  public override func startLoading()
  {
    if let url = request.url,
       let response = TestURLServer.testURLs[url]
    {
      let (chunks, response) = response(request)
      let queue = DispatchQueue(label: "url-protocol", qos: .background)

      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      queue.async {
        self.dispatchNextCommand(queue: queue, chunks: chunks)
      }
    }
    else
    {
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  public override func stopLoading() { }
}

class URLSessionTests: XCTestCase
{
  static let configuration = URLSessionConfiguration.default

  override class func setUp()
  {
    configuration.protocolClasses = [TestURLServer.self]
  }
}

//MARK: successful download requests

let textURL = baseURL.appendingPathComponent("text")
func simpleGET(_ request: URLRequest) -> ([TestURLServer.Command], HTTPURLResponse)
{
  XCTAssertEqual(request.url, textURL)
  let data = Data("Text with a 🔨".utf8)
  var headers = request.allHTTPHeaderFields ?? [:]
  headers["Content-Length"] = String(data.count)
  headers["Content-Type"] = "text/plain; charset=utf-8"
  let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)
  XCTAssert(data.count > 0)
  XCTAssertNotNil(response)
  return ([.load(data), .finishLoading], response!)
}

let slowURL = baseURL.appendingPathComponent("slow")
func slowGET(_ request: URLRequest) -> ([TestURLServer.Command], HTTPURLResponse)
{
  XCTAssertEqual(request.url, slowURL)
  let data = Data("Slowness".utf8)
  var headers = request.allHTTPHeaderFields ?? [:]
  headers["Content-Length"] = String(data.count)
  headers["Content-Type"] = "text/plain; charset=utf-8"
  let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)
  return ([.wait(0.05), .load(data), .finishLoading], response!)
}

extension URLSessionTests
{
  func testData_OK() throws
  {
    TestURLServer.register(url: textURL, response: simpleGET(_:))
    let request = URLRequest(url: textURL)
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let task = session.deferredDataTask(with: request)

    let success = task.tryMap {
      (data, response) throws -> String in
      XCTAssertEqual(response.statusCode, 200)
      guard response.statusCode == 200 else { throw TestError(response.statusCode) }
      guard let string = String(data: data, encoding: .utf8) else { throw TestError() }
      return string
    }

    let s = try success.get()
    XCTAssert(s.contains("🔨"), "Failed with error")
  }

  func testDownload_OK() throws
  {
#if os(Linux) && !swift(>=5.1.3)
    print("this test does not succeed due to a corelibs-foundation bug")
#else
    TestURLServer.register(url: textURL, response: simpleGET(_:))
    let request = URLRequest(url: textURL)
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let task = session.deferredDownloadTask(with: request)

    let handle = task.tryMap {
      (handle, response) throws -> FileHandle in
      XCTAssertEqual(response.statusCode, 200)
      guard response.statusCode == 200 else { throw TestError(response.statusCode) }
      return handle
    }
    let string = handle.tryMap {
      file throws -> String in
      defer { file.closeFile() }
      guard let string = String(data: file.availableData, encoding: .utf8) else { throw TestError() }
      return string
    }

    let s = try string.get()
    XCTAssert(s.contains("🔨"), "Failed with error")
#endif
  }
}

//MARK: requests with cancellations

extension URLSessionTests
{
  func testData_CancelDeferred() throws
  {
    let session = URLSession(configuration: .default)

    let queue = DispatchQueue(label: #function)
    var deferred: DeferredURLSessionTask<(Data, HTTPURLResponse)>! = nil
    queue.sync {
      deferred  = session.deferredDataTask(queue: queue, with: URLRequest(url: unavailableURL))
      let canceled = deferred.cancel()
      XCTAssert(canceled)
      XCTAssertEqual(deferred.state, .resolved)
    }

    do {
      let _ = try deferred.get()
      XCTFail("failed to cancel")
    }
    catch let error as Cancellation {
      XCTAssertEqual(error, Cancellation.canceled(""))
    }

    queue.sync { session.finishTasksAndInvalidate() }
  }

  func testData_CancelTask() throws
  {
    TestURLServer.register(url: slowURL, response: slowGET(_:))
    let request = URLRequest(url: slowURL)
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let queue = DispatchQueue(label: #function)
    let deferred = session.deferredDataTask(queue: queue, with: request)

    deferred.beginExecution()
    queue.sync {}

    XCTAssertNotNil(deferred.urlSessionTask)
    let canceled = deferred.cancel()
    XCTAssertEqual(canceled, true)

    do {
      let _ = try deferred.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }

    XCTAssertEqual(deferred.cancel(), false)
  }

  func testData_SuspendCancel() throws
  {
    TestURLServer.register(url: slowURL, response: slowGET(_:))
    let request = URLRequest(url: slowURL)
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let queue = DispatchQueue(label: #function)
    let deferred = session.deferredDataTask(queue: queue, with: request)

    deferred.beginExecution()
    queue.sync {}

    XCTAssertNotNil(deferred.urlSessionTask)
    let task = deferred.urlSessionTask!
    task.suspend()
    XCTAssertEqual(task.state, .suspended)

    let canceled = deferred.cancel()
    XCTAssertEqual(canceled, true)

    do {
      let _ = try deferred.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }
  }

  func testDownload_CancelDeferred() throws
  {
    let session = URLSession(configuration: .default)

    let queue = DispatchQueue(label: #function)
    var deferred: DeferredURLSessionTask<(FileHandle, HTTPURLResponse)>! = nil
    queue.sync {
      deferred = session.deferredDownloadTask(queue: queue, with: URLRequest(url: unavailableURL))
      let canceled = deferred.cancel()
      XCTAssert(canceled)
      XCTAssertEqual(deferred.state, .resolved)
    }

    do {
      let _ = try deferred.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as Cancellation {
      XCTAssertEqual(error, Cancellation.canceled(""))
    }

    queue.sync { session.finishTasksAndInvalidate() }
  }

  func testDownload_CancelTask() throws
  {
    TestURLServer.register(url: slowURL, response: slowGET(_:))
    let request = URLRequest(url: slowURL)
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let queue = DispatchQueue(label: #function)
    let deferred = session.deferredDownloadTask(queue: queue, with: request)

    deferred.beginExecution()
    queue.sync {}

    XCTAssertNotNil(deferred.urlSessionTask)
    let canceled = deferred.cancel()
    XCTAssertEqual(canceled, true)

    do {
      let _ = try deferred.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }

    XCTAssertEqual(deferred.cancel(), false)
  }

  func testDownload_SuspendCancel() throws
  {
    TestURLServer.register(url: slowURL, response: slowGET(_:))
    let request = URLRequest(url: slowURL)
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let queue = DispatchQueue(label: #function)
    let deferred = session.deferredDownloadTask(queue: queue, with: request)

    deferred.beginExecution()
    queue.sync {}

    deferred.urlSessionTask?.suspend()
    let canceled = deferred.cancel()
    XCTAssert(canceled)

    do {
      let _ = try deferred.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }
    catch URLSessionError.interruptedDownload(let error, _) {
      XCTAssertEqual(error.code, .cancelled)
    }
  }

  func testUploadData_CancelTask() throws
  {
    TestURLServer.register(url: slowURL, response: slowGET(_:))
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    var request = URLRequest(url: slowURL)
    request.httpMethod = "POST"

    let data = Data("name=John Tester&age=97".utf8)

    let queue = DispatchQueue(label: #function)
    let deferred = session.deferredUploadTask(queue: queue, with: request, fromData: data)

    deferred.beginExecution()
    queue.sync {}

    let canceled = deferred.cancel()
    XCTAssert(canceled)

    do {
      let _ = try deferred.get()
      XCTFail("failed to cancel")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }
  }
}

//MARK: requests to missing URLs

let missingURL = baseURL.appendingPathComponent("404")
func missingGET(_ request: URLRequest) -> ([TestURLServer.Command], HTTPURLResponse)
{
  let response = HTTPURLResponse(url: missingURL, statusCode: 404, httpVersion: nil, headerFields: [:])
  XCTAssertNotNil(response)
  return ([.load(Data("Not Found".utf8)), .finishLoading], response!)
}

extension URLSessionTests
{
  func testData_NotFound() throws
  {
    TestURLServer.register(url: missingURL, response: missingGET(_:))
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let request = URLRequest(url: missingURL)
    let deferred = session.deferredDataTask(with: request)

    let (data, response) = try deferred.get()
    let string = String(data: data, encoding: .utf8)
    XCTAssertEqual(string, "Not Found")
    XCTAssertEqual(response.statusCode, 404)
  }

  func testDownload_NotFound() throws
  {
#if os(Linux) && !swift(>=5.1.3)
    print("this test does not succeed due to a corelibs-foundation bug")
#else
    TestURLServer.register(url: missingURL, response: missingGET(_:))
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let request = URLRequest(url: missingURL)
    let deferred = session.deferredDownloadTask(with: request)

    let (file, response) = try deferred.get()
    defer { file.closeFile() }
    let string = String(data: file.availableData, encoding: .utf8)
    XCTAssertEqual(string, "Not Found")
    XCTAssertEqual(response.statusCode, 404)
#endif
  }
}

//MARK: request fails (not through cancellation) after some of the data is received

let failURL = baseURL.appendingPathComponent("fail-after-a-while")

func incompleteGET(_ request: URLRequest) -> ([TestURLServer.Command], HTTPURLResponse)
{
  XCTAssertEqual(request.url, failURL)
  XCTAssertEqual(request.httpMethod, "GET")
  let sizable = 2500
  let data = Data((0..<sizable).map({ UInt8(truncatingIfNeeded: $0) }))
  var headers = request.allHTTPHeaderFields ?? [:]
  headers["Content-Length"] = String(data.count)
  let response = HTTPURLResponse(url: failURL, statusCode: 200, httpVersion: nil, headerFields: headers)
  XCTAssert(data.count > 0)
  XCTAssertNotNil(response)
  let cut = Int.random(in: (data.count/2..<data.count))
  return ([.load(data[0..<cut]), .wait(0.02)], response!)
}

func partialGET(_ request: URLRequest) -> ([TestURLServer.Command], HTTPURLResponse)
{
  let (commands, response) = incompleteGET(request)
  guard case let .load(data) = commands.first! else { fatalError() }

  let error = URLError(.networkConnectionLost, userInfo: [
    "cut": data.count,
    NSURLErrorFailingURLStringErrorKey: failURL.absoluteString,
    NSLocalizedDescriptionKey: "dropped",
    NSURLErrorFailingURLErrorKey: failURL,
  ])
  return (commands + [.fail(error)], response)
}

extension URLSessionTests
{
  func testData_Incomplete() throws
  {
    TestURLServer.register(url: failURL, response: incompleteGET(_:))
    let request = URLRequest(url: failURL)
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let task = session.deferredDataTask(with: request)

    let (data, response) = try task.get()
    XCTAssertEqual(response.statusCode, 200)
    XCTAssertNotEqual(response.allHeaderFields["Content-Length"] as? String, String(data.count))
  }

  func testData_Partial() throws
  {
#if os(Linux) && !swift(>=5.1.3)
    print("this test does not succeed due to a corelibs-foundation bug")
#else
    TestURLServer.register(url: failURL, response: partialGET(_:))
    let request = URLRequest(url: failURL)
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let task = session.deferredDataTask(with: request)

    do {
      let (data, response) = try task.get()
      _ = data.count
      _ = response.statusCode
    }
    catch let error as URLError where error.code == .networkConnectionLost {
      XCTAssertNotNil(error.userInfo[NSURLErrorFailingURLStringErrorKey])
    }
#endif
  }  
}

//MARK: requests with data in HTTP body

func handleStreamedBody(_ request: URLRequest) -> ([TestURLServer.Command], HTTPURLResponse)
{
  XCTAssertNil(request.httpBody)
  XCTAssertNotNil(request.httpBodyStream)
  guard let stream = request.httpBodyStream
    else { return missingGET(request) } // happens on Linux as of core-foundation 4.2

  stream.open()
  defer { stream.close() }
  XCTAssertEqual(stream.hasBytesAvailable, true)

  let b = UnsafeMutableRawPointer.allocate(byteCount: 256, alignment: 1)
  defer { b.deallocate() }
  let read = stream.read(b.assumingMemoryBound(to: UInt8.self), maxLength: 256)
  XCTAssertGreaterThan(read, 0)
  guard let received = String(data: Data(bytes: b, count: read), encoding: .utf8),
        let url = request.url
    else { return missingGET(request) }

  XCTAssertFalse(received.isEmpty)
  let responseText = (request.httpMethod ?? "NONE") + " " + String(received.count)
  var headers = request.allHTTPHeaderFields ?? [:]
  headers["Content-Type"] = "text/plain"
  headers["Content-Length"] = String(responseText.count)
  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)
  XCTAssertNotNil(response)
  return ([.load(Data(responseText.utf8)), .finishLoading], response!)
}

func handleLinuxUploadProblem(_ request: URLRequest) -> ([TestURLServer.Command], HTTPURLResponse)
{
  XCTAssertNil(request.httpBody)
  // On Linux as of core-foundation 4.2, upload tasks do not seem to
  // make the HTTP body available in any way. It may be a problem with
  // URLProtocol mocking.
  XCTAssertNil(request.httpBodyStream) // ensure test will fail when the bug is fixed
  return missingGET(request)
}

extension URLSessionTests
{
  func testData_Post() throws
  {
    let url = baseURL.appendingPathComponent("api")
    TestURLServer.register(url: url, response: handleStreamedBody(_:))
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    let body = Data("name=Tester&age=97&data=****".utf8)
    request.httpBodyStream = InputStream(data: body)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")

    let dataTask = session.deferredDataTask(with: request)

    let (data, response) = try dataTask.get()
    XCTAssertEqual(response.statusCode, 200)
    XCTAssertGreaterThan(data.count, 0)
    let i = String(data: data, encoding: .utf8)?.components(separatedBy: " ").last
    XCTAssertEqual(i, String(body.count))
  }

  func testUploadData_OK() throws
  {
    let url = baseURL.appendingPathComponent("upload")
#if os(Linux)
    TestURLServer.register(url: url, response: handleLinuxUploadProblem(_:))
#else
    TestURLServer.register(url: url, response: handleStreamedBody(_:))
#endif
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    var request = URLRequest(url: url)
    request.httpMethod = "PUT"

    let payload = "data=" + String(repeatElement("A", count: 189)) + "🦉"
    let message = Data(payload.utf8)

    let task = session.deferredUploadTask(with: request, fromData: message)

    let (data, response) = try task.get()
#if !os(Linux)
    XCTAssertEqual(response.statusCode, 200)
    XCTAssertGreaterThan(data.count, 0)
    let i = String(data: data, encoding: .utf8)?.components(separatedBy: " ").last
    XCTAssertEqual(i, String(payload.count))
#endif
  }

  func testUploadFile_OK() throws
  {
    let url = baseURL.appendingPathComponent("upload")
#if os(Linux)
    TestURLServer.register(url: url, response: handleLinuxUploadProblem(_:))
#else
    TestURLServer.register(url: url, response: handleStreamedBody(_:))
#endif
    let session = URLSession(configuration: URLSessionTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    var request = URLRequest(url: url)
    request.httpMethod = "PUT"

    let payload = "data=" + String(repeatElement("A", count: 189)) + "🦉"
    let message = Data(payload.utf8)

#if compiler(>=5.1) || !os(Linux)
    let userDir = try FileManager.default.url(for: .desktopDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: nil,
                                              create: false)
    let tempDir = try FileManager.default.url(for: .itemReplacementDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: userDir,
                                              create: true)
#else
    let tempDir = URL(string: "file:///tmp/")!
#endif
    let fileURL = tempDir.appendingPathComponent("temporary.tmp")
    FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)

    let handle = try FileHandle(forWritingTo: fileURL)
    handle.write(message)
    handle.truncateFile(atOffset: handle.offsetInFile)
    handle.closeFile()

    let task = session.deferredUploadTask(with: request, fromFile: fileURL)

    let (data, response) = try task.get()
#if !os(Linux)
    XCTAssertEqual(response.statusCode, 200)
    XCTAssertGreaterThan(data.count, 0)
    let i = String(data: data, encoding: .utf8)?.components(separatedBy: " ").last
    XCTAssertEqual(i, String(payload.count))
#endif

    try FileManager.default.removeItem(at: fileURL)
  }
}

let invalidURL = URL(string: "unknown://url.scheme")!
extension URLSessionTests
{
  func testInvalidDataTaskURL1() throws
  {
    let request = URLRequest(url: invalidURL)
    let session = URLSession(configuration: .default)
    defer { session.finishTasksAndInvalidate() }

    let task = session.deferredDataTask(with: request)
    do {
      _ = try task.get()
      XCTFail("succeeded incorrectly")
    }
    catch Invalidation.invalid(let message) {
      XCTAssert(message.contains(request.url?.scheme ?? "$$"))
    }
  }

  func testInvalidDataTaskURL2() throws
  {
#if os(Linux) && !swift(>=5.1.3)
    print("this test does not succeed due to a corelibs-foundation bug")
#else
    let request = URLRequest(url: URL(string: "schemeless") ?? invalidURL)
    let session = URLSession(configuration: .default)
    defer { session.finishTasksAndInvalidate() }

    let task = session.deferredDataTask(with: request)
    do {
      _ = try task.get()
      XCTFail("succeeded incorrectly")
    }
    catch Invalidation.invalid(let message) {
      XCTAssert(message.contains("invalid"))
    }
#endif
  }

  func testInvalidDownloadTaskURL() throws
  {
    let request = URLRequest(url: invalidURL)
    let session = URLSession(configuration: .default)
    defer { session.finishTasksAndInvalidate() }

    let task = session.deferredDownloadTask(with: request)
    do {
      _ = try task.get()
      XCTFail("succeeded incorrectly")
    }
    catch Invalidation.invalid(let message) {
      XCTAssert(message.contains(request.url?.scheme ?? "$$"))
    }
  }

  func testInvalidUploadTaskURL1() throws
  {
    let request = URLRequest(url: invalidURL)
    let session = URLSession(configuration: .default)
    defer { session.finishTasksAndInvalidate() }

    let data = Data("data".utf8)
    let task = session.deferredUploadTask(with: request, fromData: data)
    do {
      _ = try task.get()
      XCTFail("succeeded incorrectly")
    }
    catch Invalidation.invalid(let message) {
      XCTAssert(message.contains(request.url?.scheme ?? "$$"))
    }
  }

  func testInvalidUploadTaskURL2() throws
  {
#if os(Linux) && !swift(>=5.1.3)
    print("this test does not succeed due to a corelibs-foundation bug")
#else
    let request = URLRequest(url: invalidURL)
    let session = URLSession(configuration: .default)
    defer { session.finishTasksAndInvalidate() }

    let message = Data("data".utf8)
#if compiler(>=5.1) || !os(Linux)
    let userDir = try FileManager.default.url(for: .desktopDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: nil,
                                              create: false)
    let tempDir = try FileManager.default.url(for: .itemReplacementDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: userDir,
                                              create: true)
#else
    let tempDir = URL(string: "file:///tmp/")!
#endif
    let fileURL = tempDir.appendingPathComponent("temporary.tmp")
    FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)

    let handle = try FileHandle(forWritingTo: fileURL)
    handle.write(message)
    handle.truncateFile(atOffset: handle.offsetInFile)
    handle.closeFile()
    let task = session.deferredUploadTask(with: request, fromFile: fileURL)
    do {
      _ = try task.get()
      XCTFail("succeeded incorrectly")
    }
    catch Invalidation.invalid(let message) {
      XCTAssert(message.contains(request.url?.scheme ?? "$$"))
    }
#endif
  }
}

class URLSessionResumeTests: XCTestCase
{
  static let largeLength = 100_000
  static let largeURL = baseURL.appendingPathComponent("large")
  static let largeData = Data((0..<largeLength).map({ UInt8(truncatingIfNeeded: $0) }))
  static let configuration = URLSessionConfiguration.default

  override class func setUp()
  {
    configuration.protocolClasses = [TestURLServer.self]
    TestURLServer.register(url: URLSessionResumeTests.largeURL, response: URLSessionResumeTests.largeGET(_:))
  }

  static func largeGET(_ request: URLRequest) -> ([TestURLServer.Command], HTTPURLResponse)
  {
    XCTAssertEqual(request.url, largeURL)
    let data = URLSessionResumeTests.largeData
    var headers = request.allHTTPHeaderFields ?? [:]
    // headers.forEach { (key, string) in print("\(key): \(string)") }
    if var range = headers["Range"]
    {
      XCTAssert(range.starts(with: "bytes="))
      range.removeFirst("bytes=".count)
      let bounds = range.split(separator: "-").map(String.init).compactMap(Int.init)
      XCTAssertFalse(bounds.isEmpty)
      // let length = URLSessionResumeTests.largeLength
      // headers["Content-Length"] = String(length-bounds[0])
      // headers["Content-Range"] = "bytes \(bounds[0])-\(length-1)/\(length)"
      // headers["Range"] = nil
      // headers["If-Range"] = nil
      let response = HTTPURLResponse(url: largeURL, statusCode: 206, httpVersion: nil, headerFields: headers)!
      return ([.load(data[bounds[0]...]), .finishLoading], response)
    }
    else
    {
      // headers["Content-Length"] = String(URLSessionResumeTests.largeLength)
      // headers["Accept-Ranges"] = "bytes"
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "E, d MMM yyyy HH:mm:ss z"
      headers["Last-Modified"] = formatter.string(from: Date() - 100_000 )
      let dumbCheckSum = data.reduce(0, { s, i in s &+ Int(i) })
      headers["ETag"] = "\"" + String(dumbCheckSum, radix: 16) + "\""
      let cut = Int.random(in: (data.count/3...2*(data.count/3)))
      let response = HTTPURLResponse(url: largeURL, statusCode: 200, httpVersion: nil, headerFields: headers)!
      return ([.load(data[0..<cut]), .wait(10.0), .load(data[cut...]), .finishLoading], response)
    }
  }

  func testResumeAfterCancellation() throws
  {
    let session = URLSession(configuration: URLSessionResumeTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let resumeData = Deferred<Data, Error> {
      resolver in
      let deferred = session.deferredDownloadTask(with: URLSessionResumeTests.largeURL)
      deferred.notify {
        result in
        do {
          let data = try result.get().0.availableData
          resolver.resolve(value: data)
        }
        catch URLSessionError.interruptedDownload(let error, let data) {
          XCTAssertEqual(error.code, .cancelled)
          resolver.resolve(value: data)
        }
        catch {
          resolver.resolve(error: error)
        }
      }
      deferred.timeout(seconds: 0.5)
      resolver.retainSource(deferred)
    }
#if os(Linux)
    XCTAssertNil(resumeData.value, "download did not time out")
    XCTAssertNotNil(resumeData.error)
    XCTAssert(URLError.cancelled ~= resumeData.error!)
#else
    let data = try resumeData.get()
    XCTAssertNotEqual(data, URLSessionResumeTests.largeData, "download did not time out")

    let resumed = session.deferredDownloadTask(withResumeData: data)
    let (file, response) = resumed.split()

    XCTAssertEqual(response.value?.statusCode, 206)

    let fileData = file.map(transform: { $0.availableData })
    XCTAssertEqual(try fileData.get(), URLSessionResumeTests.largeData)
#endif
  }

  func testURLRequestTimeout1() throws
  { // time out a URL request via session configuration
#if os(Linux) && !swift(>=5.1.3)
    print("this test does not succeed due to a corelibs-foundation bug")
#else
    URLSessionResumeTests.configuration.timeoutIntervalForRequest = 1.0
    let session = URLSession(configuration: URLSessionResumeTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let deferred = Deferred<(FileHandle, HTTPURLResponse), Error> {
      resolver in
      let deferred = session.deferredDownloadTask(with: URLSessionResumeTests.largeURL)
      deferred.notify { resolver.resolve($0) }
      resolver.retainSource(deferred)
    }

    do {
      let _ = try deferred.get()
    }
    catch URLSessionError.interruptedDownload(let error, let data) {
      XCTAssertEqual(error.code, .timedOut)
      XCTAssertNotEqual(data.count, 0)
    }
    catch let error as URLError where error.code == .timedOut {
      print(error, error.errorUserInfo)
    }
#endif
  }

  func testURLRequestTimeout2() throws
  { // time out a URL request via request configuration
#if os(Linux) && !swift(>=5.1.3)
    print("this test does not succeed due to a corelibs-foundation bug")
#else
    let session = URLSession(configuration: URLSessionResumeTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let deferred = Deferred<(FileHandle, HTTPURLResponse), Error> {
      resolver in
      let request = URLRequest(url: URLSessionResumeTests.largeURL, timeoutInterval: 0.5)
      let deferred = session.deferredDownloadTask(with: request)
      deferred.notify { resolver.resolve($0) }
      resolver.retainSource(deferred)
    }

    do {
      let _ = try deferred.get()
    }
    catch URLSessionError.interruptedDownload(let error, let data) {
      XCTAssertEqual(error.code, .timedOut)
      XCTAssertNotEqual(data.count, 0)
    }
    catch let error as URLError where error.code == .timedOut {
      print(error, error.errorUserInfo)
    }
#endif
  }

  func testResumeWithMangledData() throws
  {
    let session = URLSession(configuration: URLSessionResumeTests.configuration)
    defer { session.finishTasksAndInvalidate() }

    let resumeData = Deferred<Data, Error> {
      resolver in
      let deferred = session.deferredDownloadTask(with: URLSessionResumeTests.largeURL)
      deferred.onError {
        error in
        switch error
        {
        case URLSessionError.interruptedDownload(let error, let data):
          XCTAssertEqual(error.code, .cancelled)
          resolver.resolve(value: data)
        default:
          resolver.resolve(error: error)
        }
      }
      deferred.timeout(seconds: 0.5)
    }
#if os(Linux)
    XCTAssertNotNil(resumeData.error)
    XCTAssert(URLError.cancelled ~= resumeData.error!)
#else
    var data = try resumeData.get()
    // mangle the resume data
    data[200..<250] = data[500..<550]

    // Attempt to resume the download with mangled data. It should fail.
    let resumed = session.deferredDownloadTask(withResumeData: data)
    switch resumed.error
    {
    case URLSessionError.invalidState?:
      // URLSession called back with a nonsensical combination of parameters, as expected
      break
    case let error?: throw error
    case nil: XCTFail("succeeded incorrectly")
    }
#endif
  }

  func testResumeWithNonsenseData() throws
  {
    let session = URLSession(configuration: .default)
    defer { session.finishTasksAndInvalidate() }

    let nonsense = Data((0..<2345).map { UInt8.random(in: 0...UInt8(truncatingIfNeeded: $0)) })
    let task1 = session.deferredDownloadTask(withResumeData: nonsense)
    switch task1.error
    {
    case URLError.unsupportedURL?:
      XCTAssertNotNil((task1.error as? URLError)?.errorUserInfo[NSLocalizedDescriptionKey])
#if os(Linux)
      XCTAssertNil((task1.error as? URLError)?.errorUserInfo[NSUnderlyingErrorKey])
#endif
    case URLSessionError.invalidState?:
#if !os(iOS)
      XCTFail()
#endif
    case let error?: throw error
    case nil: XCTFail("succeeded incorrectly")
    }
  }

  func testResumeWithEmptyData() throws
  {
    let session = URLSession(configuration: .default)
    defer { session.finishTasksAndInvalidate() }

    let task = session.deferredDownloadTask(withResumeData: Data())
    switch task.error
    {
    case URLError.unsupportedURL?:
      XCTAssertNotNil((task.error as? URLError)?.errorUserInfo[NSLocalizedDescriptionKey])
    case URLSessionError.invalidState?:
#if !os(iOS)
      XCTFail()
#endif
    case let error?: throw error
    case nil: XCTFail("succeeded incorrectly")
    }
  }
}
