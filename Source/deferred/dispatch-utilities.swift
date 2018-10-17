//
//  dispatch-utilities.swift
//

import Dispatch
import CurrentQoS

extension DispatchQoS
{
  static func > (l: DispatchQoS, r: DispatchQoS) -> Bool
  {
    return l.isBetterThan(r)
  }
}

extension DispatchQoS.QoSClass
{
  static func > (l: DispatchQoS.QoSClass, r: DispatchQoS.QoSClass) -> Bool
  {
    return l.isBetterThan(r)
  }
}
