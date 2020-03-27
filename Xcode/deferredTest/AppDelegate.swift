//
//  AppDelegate.swift
//  deferredTest
//
//  Created by Guillaume Lessard on 6/8/18.
//  Copyright © 2018 Guillaume Lessard. All rights reserved.
//

import UIKit

import deferred
import CAtomics

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

  var window: UIWindow?

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
  {
    let tbd = Deferred<Bool, Never>() {
      resolver in
      var b = AtomicBool(false)

      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) {
        resolver.resolve(value: CAtomicsLoad(&b, .acquire))
      }

      CAtomicsStore(&b, true, .relaxed)
    }

    let c = DispatchQoS.current
    if #available(iOS 10, *)
    {
      assert(c.qosClass == DispatchQoS.userInteractive.qosClass)
    }
    else
    {
#if !targetEnvironment(simulator)
      assert(c.qosClass == DispatchQoS.userInteractive.qosClass)
#endif
    }

    tbd.onValue { assert($0) }

    return tbd.value!
  }
}

