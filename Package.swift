// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "deferred",
  products: [
    .library(name: "deferred", type: .static, targets: ["deferred"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics.git", .revision("2575543d151c992d7b0e9dd0929ee6f5482cbfdf")),
    .package(url: "https://github.com/glessard/CurrentQoS.git", from: "1.1.0"),
  ],
  targets: [
    .target(name: "deferred", dependencies: ["CAtomics", "CurrentQoS"]),
    .testTarget(name: "deferredTests", dependencies: ["deferred"]),
  ],
  swiftLanguageVersions: [.v4, .v4_2, .v5]
)
