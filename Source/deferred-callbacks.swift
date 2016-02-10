//
//  deferred-callbacks.swift
//  deferred
//
//  Created by Guillaume Lessard on 09/02/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Foundation

public extension Deferred
{
  public static func wrap<P, T>(asynchronous: (p: P, callback: (T?, NSError?) -> Void) -> Void) -> (P) -> Deferred<T>
  {
    return {
      (parameter: P) -> Deferred<T> in
      let tbd = TBD<T>()
      
      asynchronous(p: parameter) {
        (value: T?, error: NSError?) -> Void in
        if let error = error      { _ = try? tbd.determine(error) }
        else if let value = value { _ = try? tbd.determine(value) }
        else /* impossible? */    { _ = try? tbd.determine(Result()) }
      }

      return tbd
    }
  }

  public static func wrap<P1, P2, T>(
    asynchronous: (p1: P1, p2: P2, callback: (T?, NSError?) -> Void) -> Void
    ) -> (P1, P2) -> Deferred<T>
  {
    return {
      (p1: P1, p2: P2) -> Deferred<T> in
      let tbd = TBD<T>()

      asynchronous(p1: p1, p2: p2) {
        (value: T?, error: NSError?) -> Void in
        if let error = error      { _ = try? tbd.determine(error) }
        else if let value = value { _ = try? tbd.determine(value) }
        else /* impossible? */    { _ = try? tbd.determine(Result()) }
      }

      return tbd
    }
  }

  public static func wrap<P, T1, T2>(
    asynchronous: (p: P, callback: (T1?, T2?, NSError?) -> Void) -> Void
  ) -> (P) -> Deferred<(T1,T2)>
  {
    return {
      (parameter: P) -> Deferred<(T1,T2)> in
      let tbd = TBD<(T1,T2)>()

      asynchronous(p: parameter) {
        (v1: T1?, v2: T2?, error: NSError?) -> Void in
        if let error = error
        { _ = try? tbd.determine(error) }
        else if let v1 = v1, v2 = v2
        { _ = try? tbd.determine(v1, v2) }
        else /* impossible? */
        { _ = try? tbd.determine(Result()) }
      }

      return tbd
    }
  }
}
