// swift-tools-version:4.0

import PackageDescription

let package = Package(
  name: "deferred",
  products: [
    .library(name: "deferred", type: .static, targets: ["deferred"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics.git", from: "4.4.1"),
    .package(url: "https://github.com/glessard/outcome.git", from: "4.1.5"),
    .package(url: "https://github.com/glessard/CurrentQoS.git", from: "1.0.0"),
  ],
  targets: [
    .target(name: "deferred", dependencies: ["CAtomics", "Outcome", "CurrentQoS"]),
    .testTarget(name: "deferredTests", dependencies: ["deferred"]),
  ],
  swiftLanguageVersions: [4,5]
)
