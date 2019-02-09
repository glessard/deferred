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

import deferred

let baseURL = URL(string: "http://www.somewhere.com/")!
let unavailableURL = URL(string: "http://127.0.0.1:65521/image.jpg")!

public class TestURLServer: URLProtocol
{
  typealias Chunks = [Chunk]
  typealias Response = (URLRequest) -> (Chunks, HTTPURLResponse)
  static private var testURLs: [URL: Response] = [:]

  public enum Chunk
  {
    case data(Data), wait(TimeInterval)
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

  private func dispatchNextChunk(queue: DispatchQueue, chunks: [Chunk])
  {
    if let chunk = chunks.first
    {
      let chunks = chunks.dropFirst()
      switch chunk
      {
      case .data(let data):
        queue.async {
          self.client?.urlProtocol(self, didLoad: data)
          self.dispatchNextChunk(queue: queue, chunks: Array(chunks))
        }
      case .wait(let interval):
        queue.asyncAfter(deadline: .now() + interval) {
          self.dispatchNextChunk(queue: queue, chunks: Array(chunks))
        }
      }
    }
    else
    {
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  public override func startLoading()
  {
    if let url = request.url,
       let data = TestURLServer.testURLs[url]
    {
      let (chunks, response) = data(request)
      let queue = DispatchQueue(label: "url-protocol", qos: .background)

      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      dispatchNextChunk(queue: queue, chunks: chunks)
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
func simpleGET(_ request: URLRequest) -> ([TestURLServer.Chunk], HTTPURLResponse)
{
  XCTAssert(request.url == textURL)
  let data = Data("Text with a 🔨".utf8)
  var headers = request.allHTTPHeaderFields ?? [:]
  headers["Content-Length"] = String(data.count)
  headers["Content-Type"] = "text/plain; charset=utf-8"
  let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)
  XCTAssert(data.count > 0)
  XCTAssertNotNil(response)
  return ([.data(data)], response!)
}

extension URLSessionTests
{
  func testData_OK() throws
  {
    TestURLServer.register(url: textURL, response: simpleGET(_:))
    let request = URLRequest(url: textURL)
    let session = URLSession(configuration: URLSessionTests.configuration)

    let task = session.deferredDataTask(with: request)

    let success = task.map {
      (data, response) throws -> String in
      XCTAssertEqual(response.statusCode, 200)
      guard response.statusCode == 200 else { throw URLSessionError.ServerStatus(response.statusCode) }
      guard let string = String(data: data, encoding: .utf8) else { throw TestError() }
      return string
    }

    let s = try success.get()
    XCTAssert(s.contains("🔨"), "Failed with error")

    session.finishTasksAndInvalidate()
  }

  func testDownload_OK() throws
  {
#if os(Linux)
    print("this test does not succeed due to a corelibs-foundation bug")
#else
    TestURLServer.register(url: textURL, response: simpleGET(_:))
    let request = URLRequest(url: textURL)
    let session = URLSession(configuration: URLSessionTests.configuration)

    let task = session.deferredDownloadTask(with: request)

    let url = task.map {
      (url, response) throws -> URL in
      XCTAssertEqual(response.statusCode, 200)
      guard response.statusCode == 200 else { throw URLSessionError.ServerStatus(response.statusCode) }
      return url
    }
    let handle = url.map(transform: FileHandle.init(forReadingFrom:))
    let string = handle.map {
      file throws -> String in
      defer { file.closeFile() }
      guard let string = String(data: file.readDataToEndOfFile(), encoding: .utf8) else { throw TestError() }
      return string
    }

    let s = try string.get()
    XCTAssert(s.contains("🔨"), "Failed with error")

    session.finishTasksAndInvalidate()
#endif
  }
}

//MARK: requests with cancellations

extension URLSessionTests
{
  func testData_Cancellation() throws
  {
    let session = URLSession(configuration: .default)

    let deferred = session.deferredDataTask(with: unavailableURL)
    let canceled = deferred.cancel()
    XCTAssert(canceled)

    do {
      let _ = try deferred.get()
      XCTFail("failed to cancel")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }

    session.finishTasksAndInvalidate()
  }

  func testData_DoubleCancellation() throws
  {
    let deferred: DeferredURLSessionTask<(Data, HTTPURLResponse)> = {
      let session = URLSession(configuration: .default)
      defer { session.finishTasksAndInvalidate() }

      return session.deferredDataTask(with: unavailableURL)
    }()

    deferred.urlSessionTask.cancel()

    do {
      let _ = try deferred.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }

    let canceled = deferred.cancel()
    XCTAssert(canceled == false)
  }

  func testData_SuspendCancel() throws
  {
    let session = URLSession(configuration: .default)

    let deferred = session.deferredDataTask(with: unavailableURL)
    deferred.urlSessionTask.suspend()
    let canceled = deferred.cancel()
    XCTAssert(canceled)

    do {
      let _ = try deferred.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }

    session.finishTasksAndInvalidate()
  }

  func testDownload_Cancellation() throws
  {
    let session = URLSession(configuration: .default)

    let deferred = session.deferredDownloadTask(with: unavailableURL)
    let canceled = deferred.cancel()
    XCTAssert(canceled)

    do {
      let _ = try deferred.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }
    catch URLSessionError.InterruptedDownload(let error, _) {
      XCTAssertEqual(error.code, .cancelled)
    }

    session.finishTasksAndInvalidate()
  }

  func testDownload_DoubleCancellation() throws
  {
    let deferred: DeferredURLSessionTask<(URL, HTTPURLResponse)> = {
      let session = URLSession(configuration: .default)
      defer { session.finishTasksAndInvalidate() }

      return session.deferredDownloadTask(with: unavailableURL)
    }()

    deferred.urlSessionTask.cancel()

    do {
      let _ = try deferred.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }

    let canceled = deferred.cancel()
    XCTAssert(canceled == false)
  }

  func testDownload_SuspendCancel() throws
  {
    let session = URLSession(configuration: .default)

    let deferred = session.deferredDownloadTask(with: unavailableURL)
    deferred.urlSessionTask.suspend()
    let canceled = deferred.cancel()
    XCTAssert(canceled)

    do {
      let _ = try deferred.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }
    catch URLSessionError.InterruptedDownload(let error, _) {
      XCTAssertEqual(error.code, .cancelled)
    }

    session.finishTasksAndInvalidate()
  }

  func testUploadData_Cancellation() throws
  {
    let session = URLSession(configuration: .default)

    var request = URLRequest(url: unavailableURL)
    request.httpMethod = "POST"

    let data = Data("name=John Tester&age=97".utf8)

    let deferred = session.deferredUploadTask(with: request, fromData: data)
    let canceled = deferred.cancel()
    XCTAssert(canceled)

    do {
      let _ = try deferred.get()
      XCTFail("failed to cancel")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }

    session.finishTasksAndInvalidate()
  }
}

//MARK: requests to missing URLs

let missingURL = baseURL.appendingPathComponent("404")
func missingGET(_ request: URLRequest) -> ([TestURLServer.Chunk], HTTPURLResponse)
{
  let response = HTTPURLResponse(url: missingURL, statusCode: 404, httpVersion: nil, headerFields: [:])
  XCTAssertNotNil(response)
  return ([.data(Data("Not Found".utf8))], response!)
}

extension URLSessionTests
{
  func testData_NotFound() throws
  {
    TestURLServer.register(url: missingURL, response: missingGET(_:))
    let session = URLSession(configuration: URLSessionTests.configuration)

    let request = URLRequest(url: missingURL)
    let deferred = session.deferredDataTask(with: request)

    let (data, response) = try deferred.get()
    XCTAssert(data.count > 0)
    XCTAssert(response.statusCode == 404)

    session.finishTasksAndInvalidate()
  }

  func testDownload_NotFound() throws
  {
#if os(Linux)
    print("this test does not succeed due to a corelibs-foundation bug")
#else
    TestURLServer.register(url: missingURL, response: missingGET(_:))
    let session = URLSession(configuration: URLSessionTests.configuration)

    let request = URLRequest(url: missingURL)
    let deferred = session.deferredDownloadTask(with: request)

    let (path, response) = try deferred.get()
    XCTAssert(path.isFileURL)
    let file = try FileHandle(forReadingFrom: path)
    defer { file.closeFile() }
    let data = file.readDataToEndOfFile()
    XCTAssert(data.count > 0)
    XCTAssert(response.statusCode == 404)

    session.finishTasksAndInvalidate()
#endif
  }
}

//MARK: requests with data in HTTP body

func handleStreamedBody(_ request: URLRequest) -> ([TestURLServer.Chunk], HTTPURLResponse)
{
  XCTAssertNil(request.httpBody)
  XCTAssertNotNil(request.httpBodyStream)
  guard let stream = request.httpBodyStream
    else { return missingGET(request) } // happens on Linux as of core-foundation 4.2

  stream.open()
  defer { stream.close() }
  XCTAssertEqual(stream.hasBytesAvailable, true)

#if swift(>=4.1)
  let b = UnsafeMutableRawPointer.allocate(byteCount: 256, alignment: 1)
  defer { b.deallocate() }
#else
  let b = UnsafeMutableRawPointer.allocate(bytes: 256, alignedTo: 1)
  defer { b.deallocate(bytes: 256, alignedTo: 1) }
#endif
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
  return ([.data(Data(responseText.utf8))], response!)
}

func handleLinuxUploadProblem(_ request: URLRequest) -> ([TestURLServer.Chunk], HTTPURLResponse)
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

    session.finishTasksAndInvalidate()
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

    session.finishTasksAndInvalidate()
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

    var request = URLRequest(url: url)
    request.httpMethod = "PUT"

    let payload = "data=" + String(repeatElement("A", count: 189)) + "🦉"
    let message = Data(payload.utf8)

#if os(Linux)
    let tempDir = URL(string: "file:///tmp/")!
#else
    let userDir = try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    let tempDir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: userDir, create: true)
#endif
    let fileURL = tempDir.appendingPathComponent("temporary.tmp")
    if !FileManager.default.fileExists(atPath: fileURL.path)
    {
      _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
    }

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

    session.finishTasksAndInvalidate()
    try FileManager.default.removeItem(at: fileURL)
  }
}

let invalidURL = URL(string: "unknown://url.scheme")!
extension URLSessionTests
{
  func testInvalidDataTaskURL() throws
  {
    let request = URLRequest(url: invalidURL)
    let session = URLSession(configuration: .default)
    let task = session.deferredDataTask(with: request)
    do {
      _ = try task.get()
      XCTFail("succeeded incorrectly")
    }
    catch DeferredError.invalid(let message) {
      XCTAssert(message.contains(request.url?.scheme ?? "$$"))
    }
    session.finishTasksAndInvalidate()
  }

  func testInvalidDownloadTaskURL() throws
  {
    let request = URLRequest(url: invalidURL)
    let session = URLSession(configuration: .default)
    let task = session.deferredDownloadTask(with: request)
    do {
      _ = try task.get()
      XCTFail("succeeded incorrectly")
    }
    catch DeferredError.invalid(let message) {
      XCTAssert(message.contains(request.url?.scheme ?? "$$"))
    }
    session.finishTasksAndInvalidate()
  }

  func testInvalidUploadTaskURL1() throws
  {
    let request = URLRequest(url: invalidURL)
    let session = URLSession(configuration: .default)
    let data = Data("data".utf8)
    let task = session.deferredUploadTask(with: request, fromData: data)
    do {
      _ = try task.get()
      XCTFail("succeeded incorrectly")
    }
    catch DeferredError.invalid(let message) {
      XCTAssert(message.contains(request.url?.scheme ?? "$$"))
    }
    session.finishTasksAndInvalidate()
  }

  func testInvalidUploadTaskURL2() throws
  {
    let request = URLRequest(url: invalidURL)
    let session = URLSession(configuration: .default)
    let message = Data("data".utf8)
#if os(Linux)
    let tempDir = URL(string: "file:///tmp/")!
#else
    let userDir = try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    let tempDir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: userDir, create: true)
#endif
    let fileURL = tempDir.appendingPathComponent("temporary.tmp")
    if !FileManager.default.fileExists(atPath: fileURL.path)
    {
      _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
    }
    let handle = try FileHandle(forWritingTo: fileURL)
    handle.write(message)
    handle.truncateFile(atOffset: handle.offsetInFile)
    handle.closeFile()
    let task = session.deferredUploadTask(with: request, fromFile: fileURL)
    do {
      _ = try task.get()
      XCTFail("succeeded incorrectly")
    }
    catch DeferredError.invalid(let message) {
      XCTAssert(message.contains(request.url?.scheme ?? "$$"))
    }
    session.finishTasksAndInvalidate()
  }
}

class URLSessionResumeTests: XCTestCase
{
  static let largeLength = 100_000
  static let largeURL = baseURL.appendingPathComponent("large")
#if swift(>=5.0)
  static let largeData = Data((0..<largeLength).map({ UInt8(truncatingIfNeeded: $0) }))
#else
  static let largeData = Data(bytes: (0..<largeLength).map({ UInt8(truncatingIfNeeded: $0) }))
#endif
  static let configuration = URLSessionConfiguration.default

  override class func setUp()
  {
    configuration.protocolClasses = [TestURLServer.self]
    TestURLServer.register(url: URLSessionResumeTests.largeURL, response: URLSessionResumeTests.largeGET(_:))
  }

  static func largeGET(_ request: URLRequest) -> ([TestURLServer.Chunk], HTTPURLResponse)
  {
    XCTAssertEqual(request.url, largeURL)
    let data = URLSessionResumeTests.largeData
    var headers = request.allHTTPHeaderFields ?? [:]
    // headers.forEach { (key, string) in print("\(key): \(string)") }
    if var range = headers["Range"]
    {
      XCTAssert(range.starts(with: "bytes="))
      range.removeFirst("bytes=".count)
#if swift(>=4.1)
      let bounds = range.split(separator: "-").map(String.init).compactMap(Int.init)
#else
      let bounds = range.split(separator: "-").map(String.init).flatMap(Int.init)
#endif
      XCTAssertFalse(bounds.isEmpty)
      // let length = URLSessionResumeTests.largeLength
      // headers["Content-Length"] = String(length-bounds[0])
      // headers["Content-Range"] = "bytes \(bounds[0])-\(length-1)/\(length)"
      // headers["Range"] = nil
      // headers["If-Range"] = nil
      let response = HTTPURLResponse(url: largeURL, statusCode: 206, httpVersion: nil, headerFields: headers)!
      return ([.data(data[bounds[0]...])], response)
    }
    else
    {
      // headers["Content-Length"] = String(URLSessionResumeTests.largeLength)
      // headers["Accept-Ranges"] = "bytes"
      let formatter = DateFormatter()
      formatter.dateFormat = "E, d MMM yyyy HH:mm:ss z"
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      headers["Last-Modified"] = formatter.string(from: Date() - 100_000 )
      let dumbCheckSum = data.reduce(0, { s, i in s &+ Int(i) })
      headers["ETag"] = "\"" + String(dumbCheckSum, radix: 16) + "\""
      let cut = data.count/2 + 731
      let response = HTTPURLResponse(url: largeURL, statusCode: 200, httpVersion: nil, headerFields: headers)!
      return ([.data(data[0..<cut]), .wait(10.0), .data(data[cut...])], response)
    }
  }

  func testResumeAfterCancellation() throws
  {
    let session = URLSession(configuration: URLSessionResumeTests.configuration)
    let deferred = session.deferredDownloadTask(with: URLSessionResumeTests.largeURL)

    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: { deferred.cancel() })

    let mapped = deferred.map { _ in Data() }
    XCTAssertNotNil(mapped.error)
    let resumeData = mapped.recover {
      error in
      switch error
      {
      case URLSessionError.InterruptedDownload(let error, let data):
        XCTAssertEqual(error.code, .cancelled)
        return Deferred(value: data)
      default:
        return Deferred(error: error)
      }
    }
#if os(Linux)
    XCTAssertNotNil(resumeData.error)
    XCTAssert(URLError.cancelled ~= resumeData.error!)
#else
    let data = try resumeData.get()

    let resumed = session.deferredDownloadTask(withResumeData: data)
    let (url, response) = resumed.split()

    XCTAssertEqual((try response.get()).statusCode, 206)

    let fileData = url.map(transform: FileHandle.init(forReadingFrom:)).map(transform: { $0.readDataToEndOfFile() })
    XCTAssertEqual(try fileData.get(), URLSessionResumeTests.largeData)
#endif

    session.finishTasksAndInvalidate()
  }

  func testResumeWithMangledData() throws
  {
    let session = URLSession(configuration: URLSessionResumeTests.configuration)
    let deferred = session.deferredDownloadTask(with: URLSessionResumeTests.largeURL)

    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: { deferred.cancel() })
    let mapped = deferred.map { _ in Data() }
    XCTAssertNotNil(mapped.error)
    let resumeData = mapped.recover {
      error in
      switch error
      {
      case URLSessionError.InterruptedDownload(let error, let data):
        XCTAssertEqual(error.code, .cancelled)
        return Deferred(value: data)
      default:
        return Deferred(error: error)
      }
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
    do {
      let (_, _) = try resumed.get()
      XCTFail("succeeded incorrectly")
    }
    catch URLSessionError.InvalidState {
      // URLSession called back with a nonsensical combination of parameters, as expected
    }
#endif

    session.finishTasksAndInvalidate()
  }

  func testResumeWithInvalidData() throws
  {
#if swift(>=5.0)
    let nonsense = Data((0..<2345).map({ UInt8(truncatingIfNeeded: $0) }))
#else
    let nonsense = Data(bytes: (0..<2345).map({ UInt8(truncatingIfNeeded: $0) }))
#endif
    let session = URLSession(configuration: .default)
    let task1 = session.deferredDownloadTask(withResumeData: nonsense)
    do {
      _ = try task1.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError where (URLError.unsupportedURL ~= error) {
      XCTAssertNotNil(error.userInfo[NSLocalizedDescriptionKey])
#if os(Linux)
      XCTAssertNil(error.userInfo[NSUnderlyingErrorKey])
#endif
    }

    let empty = Data()
    let task2 = session.deferredDownloadTask(withResumeData: empty)
    do {
      _ = try task2.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError where (error.code == .unsupportedURL) {
      XCTAssertNotNil(error.userInfo[NSLocalizedDescriptionKey])
    }

    session.finishTasksAndInvalidate()
  }
}
