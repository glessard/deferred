//
//  dispatch-utilities.swift
//  deferred
//
//  Created by Guillaume Lessard on 13/02/2017.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

import Dispatch

// these extensions could be a separate module, but why bother

extension DispatchQoS
{
  @_versioned static var current: DispatchQoS
  {
    if let qosClass = DispatchQoS.QoSClass.current
    {
      return DispatchQoS(qosClass: qosClass, relativePriority: 0)
    }
    return .default
  }
}

extension DispatchQoS.QoSClass
{
  static var current: DispatchQoS.QoSClass?
  {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    return DispatchQoS.QoSClass(rawValue: qos_class_self())
#else // platforms that rely on swift-corelibs-libdispatch
    return nil
#endif
  }
}

extension DispatchQoS
{
  static func > (l: DispatchQoS, r: DispatchQoS) -> Bool
  {
    let lp = l.relativePriority
    if lp < -15 || lp > 0 { return false }
    let rp = r.relativePriority
    if rp < -15 || rp > 0 { return true }

    let lq = l.qosClass
    let rq = r.qosClass
    if lq == rq { return lp < rp }
    return lq > rq
  }
}

extension DispatchQoS.QoSClass
{
  static func > (l: DispatchQoS.QoSClass, r: DispatchQoS.QoSClass) -> Bool
  {
    switch (l,r)
    {
    case (.unspecified, _): return false
    case (_, .unspecified): return true
    case (.userInteractive, .userInteractive): return false
    case (.userInteractive, _): return true
    case (.userInitiated, .userInteractive): return false
    case (.userInitiated, .userInitiated): return false
    case (.userInitiated, _): return true
    case (.default, .background): return true
    case (.default, .utility): return true
    case (.utility, .background): return true
    default: return false
    }
  }
}
