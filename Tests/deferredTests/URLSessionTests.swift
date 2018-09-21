//
//  CallbackTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 09/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
import Foundation

#if false

import deferred

let basePath = "http://localhost:9973/"
let imagePath = basePath + "image.jpg"
let notFoundPath = basePath + "404"

class URLSessionTests: XCTestCase
{
#if _runtime(_ObjC)

  func testData_OK()
  {
    let url = URL(string: imagePath)!
    let request = URLRequest(url: url)
    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)

    let result = session.deferredDataTask(with: request)

    let success = result.map {
      (data, response) throws -> Data in
      guard (200..<300).contains(response.statusCode) else
      {
        throw URLSessionError.ServerStatus(response.statusCode)
      }

      return data
    }.map {
      data -> Bool in
#if os(macOS)
      let im = NSImage(data: data)
#else
      let im = UIImage(data: data)
#endif
      if let im = im
      {
        return (im.size.width == 200.0) && (im.size.height == 200.0)
      }
      return false
    }

    do {
      let success = try success.get()
      XCTAssert(success, "Failed with error")
    }
    catch {
      XCTFail(String(describing: error))
    }

    session.invalidateAndCancel()
  }

  func testData_Upload()
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

    session.invalidateAndCancel()
  }

  func testData_Cancellation()
  {
    let url = URL(string: imagePath)!
    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)

    let deferred = session.deferredDataTask(with: url)
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

    session.invalidateAndCancel()
  }

  func testData_DoubleCancellation()
  {
    let deferred: Deferred<(Data, HTTPURLResponse)> = {
      let url = URL(string: imagePath)!
      let session = URLSession(configuration: URLSessionConfiguration.ephemeral)
      defer { session.invalidateAndCancel() }

      return session.deferredDataTask(with: url)
    }()

    usleep(1000)

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

  func testData_SuspendCancel()
  {
    let url = URL(string: imagePath)!
    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)

    let deferred = session.deferredDataTask(with: url)
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

    session.invalidateAndCancel()
  }

  func testData_NotFound()
  {
    let url = URL(string: notFoundPath)!
    let request = URLRequest(url: url)
    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)

    let deferred = session.deferredDataTask(with: request)

    do {
      let (data, response) = try deferred.get()
      XCTAssert(data.count > 0)
      XCTAssert(response.statusCode == 404)
    }
    catch {
      XCTFail(String(describing: error))
    }

    session.invalidateAndCancel()
  }

  func testDownload_OK()
  {
    let url = URL(string: imagePath)!
    let request = URLRequest(url: url)
    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)

    let result = session.deferredDownloadTask(with: request)

    let success = result.map {
      (url, file, response) throws -> Data in
      guard (200..<300).contains(response.statusCode) else
      {
        throw URLSessionError.ServerStatus(response.statusCode)
      }
      defer { file.closeFile() }

      return file.readDataToEndOfFile()
    }.map {
      data -> Bool in
#if os(macOS)
      let im = NSImage(data: data)
#else
      let im = UIImage(data: data)
#endif
      if let im = im
      {
        return (im.size.width == 200.0) && (im.size.height == 200.0)
      }
      return false
    }

    do {
      let success = try success.get()
      XCTAssert(success, "Failed without error")
    }
    catch {
      XCTFail(String(describing: error))
    }

    session.invalidateAndCancel()
  }

  func testDownload_Cancellation()
  {
    let url = URL(string: imagePath)!
    let session = URLSession(configuration: URLSessionConfiguration.ephemeral)

    let deferred = session.deferredDownloadTask(with: url)
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

    session.invalidateAndCancel()
  }

  func testDownload_DoubleCancellation()
  {
    let deferred: DeferredURLSessionTask<(URL, FileHandle, HTTPURLResponse)> = {
      let url = URL(string: imagePath)!
      let session = URLSession(configuration: URLSessionConfiguration.ephemeral)
      defer { session.invalidateAndCancel() }

      return session.deferredDownloadTask(with: url)
    }()

    usleep(1000)

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

    session.invalidateAndCancel()
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
//      session.invalidateAndCancel()
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
//    waitForExpectations(withTimeout: 9.9) { _ in session.invalidateAndCancel() }
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

    session.invalidateAndCancel()
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

    session.invalidateAndCancel()
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

    session.invalidateAndCancel()
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

    session.invalidateAndCancel()
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

#endif
