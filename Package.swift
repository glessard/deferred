// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "deferred",
  products: [
    .library(name: "deferred", type: .static, targets: ["deferred"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics", from: "6.2.0"),
    .package(url: "https://github.com/glessard/CurrentQoS", from: "1.1.0"),
  ],
  targets: [
    .target(name: "deferred", dependencies: ["CAtomics", "CurrentQoS"]),
    .testTarget(name: "deferredTests", dependencies: ["deferred"]),
  ]
)
