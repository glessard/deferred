//
//  dispatchqos.swift
//  deferred
//
//  Created by Guillaume Lessard on 31/08/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import Dispatch

extension DispatchQoS
{
#if SWIFT_PACKAGE
  public static func current(fallback: DispatchQoS.QoSClass = .utility) -> DispatchQoS
  {
    return DispatchQoS(qosClass: DispatchQoS.QoSClass.current(fallback: fallback), relativePriority: 0)
  }
#else
  static func current(fallback: DispatchQoS.QoSClass = .utility) -> DispatchQoS
  {
    return DispatchQoS(qosClass: DispatchQoS.QoSClass.current(fallback: fallback), relativePriority: 0)
  }
#endif
}

extension DispatchQoS.QoSClass
{
#if SWIFT_PACKAGE
  public static func current(fallback: DispatchQoS.QoSClass = .utility) -> DispatchQoS.QoSClass
  {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
  return DispatchQoS.QoSClass(rawValue: qos_class_self()) ?? fallback
#else // platforms that rely on swift-corelibs-libdispatch
  return fallback
#endif
  }
#else
  static func current(fallback: DispatchQoS.QoSClass = .utility) -> DispatchQoS.QoSClass
  {
    return DispatchQoS.QoSClass(rawValue: qos_class_self()) ?? fallback
  }
#endif
}
