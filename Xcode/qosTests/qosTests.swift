//
//  qosTests.swift
//  qosTests
//
//  Created by Guillaume Lessard on 28/07/2016.
//  Copyright © 2016 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch

class qosTests: XCTestCase
{
  override func setUp()
  {
    super.setUp()
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }
  
  override func tearDown()
  {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }
  
  func testExample()
  {
    let g = DispatchGroup()
    let q = DispatchQueue.global(qos: .background)

    let qos = DispatchQoS(qosClass: .utility, relativePriority: -10)

    var qc: DispatchQoS.QoSClass? = nil

    print(qos.qosClass.rawValue)
    q.async(group: g, qos: qos) {
      qc = DispatchQoS.QoSClass(rawValue: qos_class_self())
      print(qos_class_self())
    }

    XCTAssertNotNil(DispatchQoS.QoSClass(rawValue: qos_class_t(0)))
    XCTAssertNil(DispatchQoS.QoSClass(rawValue: qos_class_t(.max)))
    XCTAssertNil(DispatchQoS.QoSClass(rawValue: qos_class_t(34)))

    g.wait()
    print((qc?.rawValue)!)
    print(DispatchQoS.QoSClass(rawValue: qos_class_t(0))!)
  }

  func work1(qos: qos_class_t = qos_class_self())
  {
    
  }

  func work2(qos: DispatchQoS = DispatchQoS(qosClass: DispatchQoS.QoSClass(rawValue: qos_class_self()) ?? .unspecified, relativePriority: 0))
  {

  }

  func work3(qos: DispatchQoS = DispatchQoS(qosClass: DispatchQoS.QoSClass(rawValue: qos_class_self())!, relativePriority: 0))
  {

  }
}
