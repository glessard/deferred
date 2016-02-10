//
//  CallbackTests.swift
//  deferred
//
//  Created by Guillaume Lessard on 09/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest

import deferred

enum HTTPError: ErrorType
{
  case ServerStatus(Int)
  case InvalidState
}

class URLSessionTests: XCTestCase
{
  func testURL1()
  {
    let url = NSURL(string: "https://www.gravatar.com/avatar/3797130f79b69ac59b8540bffa4c96fa?s=200")!
    let request = NSURLRequest(URL: url)
    let session = NSURLSession(configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration())

    func deferredRequest(request: NSURLRequest) -> Deferred<(NSData, NSHTTPURLResponse)>
    {
      let tbd = TBD<(NSData, NSHTTPURLResponse)>()

      let task = session.dataTaskWithRequest(request) {
        (data: NSData?, response: NSURLResponse?, error: NSError?) in
        if let error = error
        { _ = try? tbd.determine(error) }
        else if let d = data, r = response as? NSHTTPURLResponse
        { _ = try? tbd.determine( (d,r) ) }
        else
        { _ = try? tbd.determine(HTTPError.InvalidState) }
      }
      task.resume()
      tbd.onError { _ in task.cancel() }
      return tbd
    }

    let result = deferredRequest(request)
    // result.cancel()

    let e = expectationWithDescription("Image saved to /tmp/image")

    result.onValue {
      (imageData, response) in
      guard (200..<300).contains(response.statusCode) else
      {
        XCTFail()
        return
      }

      let path = "/tmp/image"
      if !NSFileManager.defaultManager().fileExistsAtPath(path)
      {
        NSFileManager.defaultManager().createFileAtPath(path, contents: nil, attributes: nil)
      }
      if let f = NSFileHandle(forWritingAtPath: path)
      {
        f.writeData(imageData)
        f.closeFile()
      }

      e.fulfill()
    }

    waitForExpectationsWithTimeout(1.0) { _ in session.invalidateAndCancel() }
  }

  func testURL2()
  {
    let url = NSURL(string: "https://www.gravatar.com/avatar/00000000000000000000000000000000?d=404")!
    let request = NSURLRequest(URL: url)
    let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())

    func deferredRequest(request: NSURLRequest) -> Deferred<(NSData, NSHTTPURLResponse)>
    {
      let tbd = TBD<(NSData, NSHTTPURLResponse)>()

      let task = session.dataTaskWithRequest(request) {
        (data: NSData?, response: NSURLResponse?, error: NSError?) in
        if let error = error
        { _ = try? tbd.determine(error) }
        else if let d = data, r = response as? NSHTTPURLResponse
        { _ = try? tbd.determine( (d,r) ) }
        else
        { _ = try? tbd.determine(HTTPError.InvalidState) }
      }
      task.resume()
      tbd.onError { _ in task.cancel() }
      return tbd
    }

    let result = deferredRequest(request)

    let e = expectationWithDescription("Image not found")

    result.onValue {
      (imageData, response) in
      guard !(200..<300).contains(response.statusCode) else
      {
        XCTFail()
        return
      }

      if response.statusCode == 404 { e.fulfill() }
    }

    waitForExpectationsWithTimeout(1.0) { _ in session.invalidateAndCancel() }
  }
}
