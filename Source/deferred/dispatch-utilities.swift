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
  @_versioned static var current: DispatchQoS?
  {
    if let qosClass = DispatchQoS.QoSClass.current
    {
      return DispatchQoS(qosClass: qosClass, relativePriority: 0)
    }
    return nil
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

extension DispatchQueue
{
  func async(qos: DispatchQoS?, execute closure: @escaping () -> Void)
  {
    if let qos = qos
    {
      self.async(qos: qos, flags: [.enforceQoS], execute: closure)
    }
    else
    {
      self.async(execute: closure)
    }
  }
}
