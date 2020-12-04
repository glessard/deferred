// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "deferred",
  products: [
    .library(name: "deferred", targets: ["deferred"]),
  ],
  dependencies: [
    .package(url: "https://github.com/glessard/CAtomics", from: "6.5.0"),
    .package(url: "https://github.com/glessard/CurrentQoS", from: "1.1.0"),
  ],
  targets: [
    .target(name: "deferred", dependencies: ["CAtomics", "CurrentQoS"]),
    .testTarget(name: "deferredTests", dependencies: ["deferred"]),
  ]
)
