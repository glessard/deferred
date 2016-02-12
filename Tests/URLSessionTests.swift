//
//  CallbackTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 09/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest

import deferred

let imagePath = "https://www.gravatar.com/avatar/3797130f79b69ac59b8540bffa4c96fa?s=200"
let largerPath = "https://www.gravatar.com/avatar/3797130f79b69ac59b8540bffa4c96fa?s=2048"
let notFoundPath = "https://www.gravatar.com/avatar/00000000000000000000000000000000?d=404"

class URLSessionTests: XCTestCase
{
#if _runtime(_ObjC)

  func testData_OK()
  {
    let url = NSURL(string: imagePath)!
    let request = NSURLRequest(URL: url)
    let session = NSURLSession(configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration())

    let result = session.deferredDataTask(request)

    let path = NSTemporaryDirectory() + "image.jpg"
    let e = expectationWithDescription("Image saved to " + path)

    result.map {
      (data, response) throws -> NSData in
      guard (200..<300).contains(response.statusCode) else
      {
        XCTFail()
        throw URLSessionError.ServerStatus(response.statusCode)
      }

      return data
    }.map {
      (data) throws -> (NSData, NSFileHandle) in
      if !NSFileManager.defaultManager().fileExistsAtPath(path)
      {
        NSFileManager.defaultManager().createFileAtPath(path, contents: nil, attributes: nil)
      }

      let url = NSURL(string: "file://" + path)!
      let handle = try NSFileHandle(forWritingToURL: url)

      return (data, handle)
    }.notify {
      result in
      switch result
      {
      case .Value(let (data, handle)):
        handle.writeData(data)
        handle.closeFile()
        e.fulfill()
      case .Error(let error):
        print(error)
        XCTFail()
      }
    }

    waitForExpectationsWithTimeout(1.0) { _ in session.invalidateAndCancel() }
  }

  func testData_Cancellation()
  {
    let url = NSURL(string: imagePath)!
    let session = NSURLSession(configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration())

    let deferred = session.deferredDataTask(url)
    let canceled = deferred.cancel()
    XCTAssert(canceled)

    if let error = deferred.error
    {
      let e = error as NSError
      XCTAssert(e.domain == NSURLErrorDomain)
      XCTAssert(e.code == NSURLErrorCancelled)
    }
    else
    {
      XCTFail()
    }

    session.invalidateAndCancel()
  }

  func testData_SuspendCancel()
  {
    let url = NSURL(string: largerPath)!
    let session = NSURLSession(configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration())

    let deferred = session.deferredDataTask(url)
    deferred.task?.suspend()
    let canceled = deferred.cancel()
    XCTAssert(canceled)

    if let error = deferred.error
    {
      XCTAssertFalse(error is DeferredError)
      let e = error as NSError
      XCTAssert(e.domain == NSURLErrorDomain)
      XCTAssert(e.code == NSURLErrorCancelled)
    }
    else
    {
      XCTFail()
    }

    session.invalidateAndCancel()
  }

  func testData_NotFound()
  {
    let url = NSURL(string: notFoundPath)!
    let request = NSURLRequest(URL: url)
    let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())

    let deferred = session.deferredDataTask(request)

    if let (data, response) = deferred.value
    {
      let control = "404 Not Found".withCString { NSData(bytes: UnsafePointer<Void>($0), length: 13) }
      XCTAssert(data.isEqualToData(control))
      XCTAssert(response.statusCode == 404)
    }
    else
    {
      XCTFail()
    }

    session.invalidateAndCancel()
  }

  func testDownload_OK()
  {
    let url = NSURL(string: imagePath)!
    let request = NSURLRequest(URL: url)
    let session = NSURLSession(configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration())

    let result = session.deferredDownloadTask(request)

    let path = NSTemporaryDirectory() + "image.jpg"
    let e = expectationWithDescription("Image saved to " + path)

    result.map {
      (url, file, response) throws -> NSData in
      guard (200..<300).contains(response.statusCode) else
      {
        XCTFail()
        throw URLSessionError.ServerStatus(response.statusCode)
      }
      defer { file.closeFile() }
      // print(url)

      return file.readDataToEndOfFile()
    }.map {
      (data) throws -> (NSData, NSFileHandle) in
      if !NSFileManager.defaultManager().fileExistsAtPath(path)
      {
        NSFileManager.defaultManager().createFileAtPath(path, contents: nil, attributes: nil)
      }

      let url = NSURL(string: "file://" + path)!
      let handle = try NSFileHandle(forWritingToURL: url)

      return (data, handle)
    }.notify {
      result in
      switch result
      {
      case .Value(let (data, handle)):
        handle.writeData(data)
        handle.truncateFileAtOffset(handle.offsetInFile)
        handle.closeFile()
        e.fulfill()
      case .Error(let error):
        print(error)
        XCTFail()
      }
    }

    waitForExpectationsWithTimeout(1.0) { _ in session.invalidateAndCancel() }
  }

  func testDownload_Cancellation()
  {
    let url = NSURL(string: imagePath)!
    let session = NSURLSession(configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration())

    let deferred = session.deferredDownloadTask(url)
    let canceled = deferred.cancel()
    XCTAssert(canceled)

    if let error = deferred.error
    {
      let e = error as NSError
      XCTAssert(e.domain == NSURLErrorDomain)
      XCTAssert(e.code == NSURLErrorCancelled)
    }
    else
    {
      XCTFail()
    }

    session.invalidateAndCancel()
  }

  func testDownload_SuspendCancel()
  {
    let url = NSURL(string: largerPath)!
    let session = NSURLSession(configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration())

    let deferred = session.deferredDownloadTask(url)
    deferred.task?.suspend()
    let canceled = deferred.cancel()
    XCTAssert(canceled)

    if let error = deferred.error
    {
      XCTAssertFalse(error is DeferredError)
      let e = error as NSError
      XCTAssert(e.domain == NSURLErrorDomain)
      XCTAssert(e.code == NSURLErrorCancelled)
    }
    else
    {
      XCTFail()
    }

    session.invalidateAndCancel()
  }

  func testDownload_CancelAndResume()
  {
    let url = NSURL(string: "https://mirrors.axint.net/repos/gnu.org/gcc/gcc-2.8.0.tar.gz")!
    let session = NSURLSession(configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration())

    let deferred = session.deferredDownloadTask(url)
    usleep(250_000)
    let canceled = deferred.cancel()
    XCTAssert(canceled)
    XCTAssert(deferred.error != nil)

    let converted = deferred.map { _ -> Result<NSData> in Result() }
    XCTAssert(converted.value == nil)

    let recovered = converted.recover {
      error in
      do { throw error }
      catch URLSessionError.InterruptedDownload(let data) {
        return Deferred(value: data)
      }
      catch {
        return Deferred(error: error)
      }
    }
    if let error = recovered.error
    { // give up
      print(error)
      XCTFail("Data download failed")
      session.invalidateAndCancel()
      return
    }

    let firstLength = recovered.map { data in data.length }

    let resumed = recovered.flatMap { data in session.deferredDownloadTask(data) }
    let finalLength = resumed.map {
      (url, handle, response) throws -> Int in
      defer { handle.closeFile() }

      var ptr = Optional<AnyObject>()
      try url.getResourceValue(&ptr, forKey: NSURLFileSizeKey)

      if let number = ptr as? NSNumber
      {
        return number.integerValue
      }
      if let error = Result<Void>().error { throw error }
      return -1
    }

    let e = expectationWithDescription("Large file download, paused and resumed")

    combine(firstLength, finalLength).onValue {
      (l1, l2) in
      // print(l2)
      XCTAssert(l2 > l1)
      e.fulfill()
    }

    waitForExpectationsWithTimeout(9.9) { _ in session.invalidateAndCancel() }
  }

  func testDownload_NotFound()
  {
    let url = NSURL(string: notFoundPath)!
    let request = NSURLRequest(URL: url)
    let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())

    let deferred = session.deferredDownloadTask(request)

    if let (_, handle, response) = deferred.value
    {
      let data = handle.readDataToEndOfFile()
      handle.closeFile()
      let control = "404 Not Found".withCString { NSData(bytes: UnsafePointer<Void>($0), length: 13) }
      XCTAssert(data.isEqualToData(control))
      XCTAssert(response.statusCode == 404)
    }
    else
    {
      XCTFail()
    }

    session.invalidateAndCancel()
  }

#endif
}
