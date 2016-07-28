//
//  string-data-util.swift
//  deferred
//
//  Created by Guillaume Lessard on 17/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Foundation

extension String
{
  public init(fromData data: Data)
  {
    self = String(data: data, encoding: String.Encoding.utf8) ?? ""
  }
}

extension NSData
{
  public convenience init(fromString string: String)
  {
    let utf8 = string.utf8
    let count = utf8.count
    let buffer = UnsafeMutablePointer<UTF8.CodeUnit>.allocate(capacity: count)
    buffer.initialize(from: utf8)
    self.init(bytesNoCopy: buffer, length: count,
              deallocator: { _ in buffer.deallocate(capacity: count) })
  }
}

