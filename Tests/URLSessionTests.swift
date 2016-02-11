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
let notFoundPath = "https://www.gravatar.com/avatar/00000000000000000000000000000000?d=404"

class URLSessionTests: XCTestCase
{
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
}
