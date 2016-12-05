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
    let qos: DispatchQoS.QoSClass
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    qos = DispatchQoS.QoSClass(rawValue: qos_class_self()) ?? fallback
#else // platforms that rely on swift-corelibs-libdispatch
    qos = fallback
#endif
    return DispatchQoS(qosClass: qos, relativePriority: 0)
  }
#else
  static func current(fallback: DispatchQoS.QoSClass = .utility) -> DispatchQoS
  {
    let qos = DispatchQoS.QoSClass(rawValue: qos_class_self()) ?? fallback
    return DispatchQoS(qosClass: qos, relativePriority: 0)
  }
#endif
}
