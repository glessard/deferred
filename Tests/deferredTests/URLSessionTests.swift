//
//  CallbackTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 09/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation

import deferred

let baseURL = URL(string: "http://www.somewhere.com/")!

//let basePath = "http://localhost:9973/"
//let imagePath = basePath + "image.jpg"
//let notFoundPath = basePath + "404"

public class TestURLServer: URLProtocol
{
  static private var testURLs: [URL: (URLRequest) -> (Data, HTTPURLResponse)] = [:]

  static func register(url: URL, response: @escaping (URLRequest) -> (Data, HTTPURLResponse))
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

  public override func startLoading()
  {
    if let url = request.url,
       let data = TestURLServer.testURLs[url]
    {
      let (data, response) = data(request)

      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
    }

    client?.urlProtocolDidFinishLoading(self)
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

  func testData_OK_Standard() throws
  {
    let textURL = baseURL.appendingPathComponent("text")

    TestURLServer.register(url: textURL) {
      request -> (Data, HTTPURLResponse) in
      XCTAssert(request.url == textURL)
      let data = Data("Text with a 🔨".utf8)
      var headers = request.allHTTPHeaderFields ?? [:]
      headers["Content-Length"] = String(data.count)
      let response = HTTPURLResponse(url: textURL, statusCode: 200, httpVersion: nil, headerFields: headers)
      XCTAssert(data.count > 0)
      XCTAssertNotNil(response)
      return (data, response!)
    }

    let request = URLRequest(url: textURL)
    let session = URLSession(configuration: URLSessionTests.configuration)

    let e = expectation(description: "data task")
    let task = session.dataTask(with: request) {
      (data: Data?, response: URLResponse?, error: Error?) in
      print(data.map(String.init(describing:)) ?? "no data")
      print(response.map(String.init(describing:)) ?? "no response")
      if let r = response as? HTTPURLResponse { print(r.statusCode) }
      print(response?.mimeType ?? "no mime type")
      print(response?.textEncodingName ?? "no text encoding")
      print(response?.expectedContentLength ?? -1)
      print(error.map(String.init(describing:)) ?? "no error")
      print(data.flatMap({ String(data: $0, encoding: .utf8) }) ?? "no string")
      e.fulfill()
    }

    task.resume()
    waitForExpectations(timeout: 1.0)
  }

  func testData_OK() throws
  {
    let textURL = baseURL.appendingPathComponent("text")

    TestURLServer.register(url: textURL) {
      request -> (Data, HTTPURLResponse) in
      XCTAssert(request.url == textURL)
      let data = Data("Text with a 🔨".utf8)
      var headers = request.allHTTPHeaderFields ?? [:]
      headers["Content-Length"] = String(data.count)
      let response = HTTPURLResponse(url: textURL, statusCode: 200, httpVersion: nil, headerFields: headers)
      XCTAssert(data.count > 0)
      XCTAssertNotNil(response)
      return (data, response!)
    }

    let request = URLRequest(url: textURL)
    let session = URLSession(configuration: URLSessionTests.configuration)

    let task = session.deferredDataTask(with: request)

    let success = task.map {
      (data, response) throws -> String in
      if !(200..<300).contains(response.statusCode)
      {
        throw URLSessionError.ServerStatus(response.statusCode)
      }
      guard let string = String(data: data, encoding: .utf8) else { throw TestError() }
      return string
    }

    let s = try success.get()
    XCTAssert(s.contains("🔨"), "Failed with error")

    session.finishTasksAndInvalidate()
  }

  func testData_Cancellation() throws
  {
    let url = baseURL.appendingPathComponent("image.jpg")
    let session = URLSession(configuration: URLSessionTests.configuration)

    TestURLServer.register(url: url) {
      request -> (Data, HTTPURLResponse) in
      XCTAssert(request.url == url)
      let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: request.allHTTPHeaderFields)
      XCTAssertNotNil(response)
      return (Data("Not Found".utf8), response!)
    }

    let deferred = session.deferredDataTask(with: url)
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
    let deferred: Deferred<(Data, HTTPURLResponse)> = {
      let url = URL(string: "http://localhost:9973/image.jpg")!
      let session = URLSession(configuration: URLSessionConfiguration.default)
      defer { session.finishTasksAndInvalidate() }

      return session.deferredDataTask(with: url)
    }()

    usleep(1000)

    do {
      let _ = try deferred.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cannotConnectToHost)
    }

    let canceled = deferred.cancel()
    XCTAssert(canceled == false)
  }

  func testData_SuspendCancel() throws
  {
    let url = URL(string: "http://localhost:9973/image.jpg")!
    let session = URLSession(configuration: URLSessionConfiguration.default)

    let deferred = session.deferredDataTask(with: url)
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

  func testData_NotFound() throws
  {
    let url = baseURL.appendingPathComponent("404")
    let session = URLSession(configuration: URLSessionTests.configuration)

    TestURLServer.register(url: url) {
      request -> (Data, HTTPURLResponse) in
      XCTAssert(request.url == url)
      let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: request.allHTTPHeaderFields)
      XCTAssertNotNil(response)
      return (Data("Not Found".utf8), response!)
    }

    let request = URLRequest(url: url)
    let deferred = session.deferredDataTask(with: request)

    let (data, response) = try deferred.get()
    XCTAssert(data.count > 0)
    XCTAssert(response.statusCode == 404)

    session.finishTasksAndInvalidate()
  }

#if false

  func testData_Post()
  {
    let url = URL(string: basePath)!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = String("name=John Tester&age=97&data=****").data(using: .utf8)

    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)
    let dataTask = session.deferredDataTask(with: request)

    do {
      let (data, response) = try dataTask.get()
      XCTAssert(response.statusCode == 200)
      XCTAssert(data.count > 0)
      if let i = String(data: data, encoding: .utf8)?.components(separatedBy: " ").last
      {
        XCTAssert(Int(i) == 4)
      }
      else { XCTFail("unexpected data in response") }
    }
    catch {
      XCTFail(String(describing: error))
    }

    session.finishTasksAndInvalidate()
  }

#endif

  func testDownload_OK() throws
  {
    let textURL = baseURL.appendingPathComponent("text")

    TestURLServer.register(url: textURL) {
      request -> (Data, HTTPURLResponse) in
      XCTAssert(request.url == textURL)
      let data = Data("Text with a 🔨".utf8)
      var headers = request.allHTTPHeaderFields ?? [:]
      headers["Content-Length"] = String(data.count)
      let response = HTTPURLResponse(url: textURL, statusCode: 200, httpVersion: nil, headerFields: headers)
      XCTAssert(data.count > 0)
      XCTAssertNotNil(response)
      return (data, response!)
    }

    let request = URLRequest(url: textURL)
    let session = URLSession(configuration: URLSessionTests.configuration)

    let task = session.deferredDownloadTask(with: request)

    let success = task.map {
      (url, file, response) throws -> String in
      if !(200..<300).contains(response.statusCode)
      {
        throw URLSessionError.ServerStatus(response.statusCode)
      }
      defer { file.closeFile() }

      return String(data: file.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    let s = try success.get()
    XCTAssert(s.contains("🔨"), "Failed with error")

    session.finishTasksAndInvalidate()
  }

  func testDownload_Cancellation() throws
  {
    let url = baseURL.appendingPathComponent("image.jpg")
    let session = URLSession(configuration: URLSessionTests.configuration)

    TestURLServer.register(url: url) {
      request -> (Data, HTTPURLResponse) in
      XCTAssert(request.url == url)
      let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: request.allHTTPHeaderFields)
      XCTAssertNotNil(response)
      return (Data("Not Found".utf8), response!)
    }

    let deferred = session.deferredDownloadTask(with: url)
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

  func testDownload_DoubleCancellation() throws
  {
    let deferred: DeferredURLSessionTask<(URL, FileHandle, HTTPURLResponse)> = {
      let url = URL(string: "http://localhost:9973/image.jpg")!
      let session = URLSession(configuration: URLSessionConfiguration.default)
      defer { session.finishTasksAndInvalidate() }

      return session.deferredDownloadTask(with: url)
    }()

    usleep(1000)

    do {
      let _ = try deferred.get()
      XCTFail("succeeded incorrectly")
    }
    catch let error as URLError {
      XCTAssertEqual(error.code, .cannotConnectToHost)
    }

    if let e = deferred.error as? URLError
    {
      _ = e
      // print(e.code.rawValue)
    }
    else
    {
      XCTFail("failed to cancel?")
    }

    let canceled = deferred.cancel()
    XCTAssert(canceled == false)
  }

  #if false

  func testDownload_SuspendCancel()
  {
    let url = URL(string: imagePath)!
    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)

    let deferred = session.deferredDownloadTask(with: url)
    deferred.urlSessionTask.suspend()
    let canceled = deferred.cancel()
    XCTAssert(canceled)

    if let e = deferred.error as? URLError
    {
      XCTAssert(e.code == .cancelled)
    }
    else
    {
      XCTFail("failed to cancel?")
    }

    session.finishTasksAndInvalidate()
  }

//  func testDownload_CancelAndResume()
//  {
//    let url = URL(string: "")!
//    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)
//
//    let deferred = session.deferredDownloadTask(url)
//
//    let converted = deferred.map { _ -> Result<NSData> in Result() }
//    usleep(250_000)
//
//    let canceled = deferred.cancel()
//    XCTAssert(canceled)
//
//    XCTAssert(deferred.error != nil)
//    XCTAssert(converted.value == nil)
//
//    let recovered = converted.recover {
//      error in
//      switch error
//      {
//      case URLSessionError.InterruptedDownload(let data):
//        return Deferred(value: data)
//      default:
//        return Deferred(error: error)
//      }
//    }
//    if let error = recovered.error
//    { // give up
//      XCTFail("Download operation failed and/or could not be resumed: \(error as NSError)")
//      session.finishTasksAndInvalidate()
//      return
//    }
//
//    let firstLength = recovered.map { data in data.length }
//
//    let resumed = recovered.flatMap { data in session.deferredDownloadTask(resumeData: data) }
//    let finalLength = resumed.map {
//      (url, handle, response) throws -> Int in
//      defer { handle.closeFile() }
//
//      XCTAssert(response.statusCode == 206)
//
//      var ptr = Optional<AnyObject>()
//      try url.getResourceValue(&ptr, forKey: URLFileSizeKey)
//
//      if let number = ptr as? NSNumber
//      {
//        return number.integerValue
//      }
//      if case let .error(error) = Result<Void>() { throw error }
//      return -1
//    }
//
//    let e = expectation(withDescription: "Large file download, paused and resumed")
//
//    combine(firstLength, finalLength).onValue {
//      (l1, l2) in
//      // print(l2)
//      XCTAssert(l2 > l1)
//      e.fulfill()
//    }
//
//    waitForExpectations(withTimeout: 9.9) { _ in session.finishTasksAndInvalidate() }
//  }

  func testDownload_NotFound()
  {
    let url = URL(string: notFoundPath)!
    let request = URLRequest(url: url)
    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)

    let deferred = session.deferredDownloadTask(with: request)

    do {
      let (_, handle, response) = try deferred.get()
      let data = handle.readDataToEndOfFile()
      handle.closeFile()
      XCTAssert(data.count > 0)
      XCTAssert(response.statusCode == 404)
    }
    catch {
      XCTFail(String(describing: error))
    }

    session.finishTasksAndInvalidate()
  }

  func testUploadData_Cancellation()
  {
    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)

    let url = URL(string: basePath)!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    let data = String("name=John Tester&age=97").data(using: .utf8)!

    let deferred = session.deferredUploadTask(with: request, fromData: data)
    let canceled = deferred.cancel()
    XCTAssert(canceled)

    if let e = deferred.error as? URLError
    {
      XCTAssert(e.code == .cancelled)
    }
    else
    {
      XCTFail("failed to cancel?")
    }

    session.finishTasksAndInvalidate()
  }

  func uploadData_OK(method: String)
  {
    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)

    let url = URL(string: basePath)!
    var request = URLRequest(url: url)
    request.httpMethod = method

    let payload = "data=" + String(repeatElement("A", count: 1995))
    let length = payload.count
    let message = payload.data(using: .utf8)!
    XCTAssert(message.count == length)

    let task = session.deferredUploadTask(with: request, fromData: message)

    do {
      let (data, response) = try task.get()
      XCTAssert(response.statusCode == 200)
      XCTAssert(task.urlSessionTask.countOfBytesSent == Int64(length))

      if let reply = String(data: data, encoding: .utf8),
         let text = reply.components(separatedBy: " ").last,
         let tlen = Int(text)
      {
        XCTAssert(tlen == length-5)
      }
      else
      {
        XCTFail("Unexpected data in response")
      }
    }
    catch {
      XCTFail(String(describing: error))
    }

    session.finishTasksAndInvalidate()
  }

  func testUploadData_POST_OK()
  {
    uploadData_OK(method: "POST")
  }

  func testUploadData_PUT_OK()
  {
    uploadData_OK(method: "PUT")
  }

  func uploadFile_OK(method: String)
  {
    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)

    let url = URL(string: basePath)!
    var request = URLRequest(url: url)
    request.httpMethod = method

    let payload = "data=" + String(repeatElement("A", count: 1995))
    let length = payload.count
    let message = payload.data(using: .utf8)!
    XCTAssert(message.count == length)

    let path = NSTemporaryDirectory() + "temporary.tmp"
    if !FileManager.default.fileExists(atPath: path)
    {
      FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
    }

    let fileurl = URL(string: "file://" + path)!
    guard let handle = try? FileHandle(forWritingTo: fileurl) else
    {
      XCTFail("could not open temporary file")
      return
    }

    handle.write(message)
    handle.truncateFile(atOffset: handle.offsetInFile)
    handle.closeFile()

    let task = session.deferredUploadTask(with: request, fromFile: fileurl)

    do {
      let (data, response) = try task.get()
      XCTAssert(response.statusCode == 200)
      XCTAssert(task.urlSessionTask.countOfBytesSent == Int64(length))

      if let reply = String(data: data, encoding: .utf8),
         let text = reply.components(separatedBy: " ").last,
         let tlen = Int(text)
      {
        XCTAssert(tlen == length-5)
      }
      else
      {
        XCTFail("Unexpected data in response")
      }
    }
    catch {
      XCTFail(String(describing: error))
    }

    session.finishTasksAndInvalidate()
  }

  func testUploadFile_POST_OK()
  {
    uploadFile_OK(method: "POST")
  }

  func testUploadFile_PUT_OK()
  {
    uploadFile_OK(method: "PUT")
  }

#endif
}
