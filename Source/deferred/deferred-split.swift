//
//  deferred-split.swift
//  deferred
//
//  Created by Guillaume Lessard on 2/1/19.
//  Copyright © 2019 Guillaume Lessard. All rights reserved.
//

extension Deferred
{
  public func split<T1, T2>() -> (Deferred<T1>, Deferred<T2>)
    where Value == (T1, T2)
  {
    let d1 = map(transform: { $0.0 })
    let d2 = map(transform: { $0.1 })

    return (d1, d2)
  }

  public func split<T1, T2, T3>() -> (Deferred<T1>, Deferred<T2>, Deferred<T3>)
    where Value == (T1, T2, T3)
  {
    let d1 = map(transform: { $0.0 })
    let d2 = map(transform: { $0.1 })
    let d3 = map(transform: { $0.2 })

    return (d1, d2, d3)
  }

  public func split<T1, T2, T3, T4>() -> (Deferred<T1>, Deferred<T2>, Deferred<T3>, Deferred<T4>)
    where Value == (T1, T2, T3, T4)
  {
    let d1 = map(transform: { $0.0 })
    let d2 = map(transform: { $0.1 })
    let d3 = map(transform: { $0.2 })
    let d4 = map(transform: { $0.3 })

    return (d1, d2, d3, d4)
  }
}
