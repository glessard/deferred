// swift-tools-version:4.2

import PackageDescription

let package = Package(
  name: "deferred",
  products: [
    .library(name: "deferred", type: .static, targets: ["deferred"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/swift-atomics.git", .revision("2ede65e5947d68440778d2d6bbceb1dfdafc6f9a")),
    .package(url: "https://github.com/glessard/outcome.git", from: "4.2.0"),
    .package(url: "https://github.com/glessard/CurrentQoS.git", from: "1.1.0"),
  ],
  targets: [
    .target(name: "deferred", dependencies: ["CAtomics", "Outcome", "CurrentQoS"]),
    .testTarget(name: "deferredTests", dependencies: ["deferred"]),
  ],
  swiftLanguageVersions: [.v4, .v4_2, .version("5")]
)
