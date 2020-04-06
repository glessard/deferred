// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "deferred",
  products: [
    .library(name: "deferred", type: .static, targets: ["deferred"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/SwiftCompatibleAtomics", .upToNextMinor(from: "0.6.0")),
    .package(url: "https://github.com/glessard/CurrentQoS", from: "1.1.0"),
  ],
  targets: [
    .target(name: "deferred", dependencies: ["SwiftCompatibleAtomics", "CurrentQoS"]),
    .testTarget(name: "deferredTests", dependencies: ["deferred"]),
  ],
  swiftLanguageVersions: [.v4, .v4_2, .v5]
)
