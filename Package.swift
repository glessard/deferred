// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "deferred",
  products: [
    .library(name: "deferred", type: .static, targets: ["deferred"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics.git", from: "5.0.0"),
    .package(url: "https://github.com/glessard/CurrentQoS.git", from: "1.1.0"),
  ],
  targets: [
    .target(name: "deferred", dependencies: ["SwiftAtomics", "CurrentQoS"]),
    .testTarget(name: "deferredTests", dependencies: ["deferred"]),
  ],
  swiftLanguageVersions: [.v4, .v4_2, .v5]
)
