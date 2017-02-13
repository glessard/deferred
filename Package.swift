import PackageDescription

let package = Package(
  name: "deferred",
  targets: [
    Target(name: "deferred"),
  ],
  dependencies: [
    .Package(url: "https://github.com/glessard/syncprint.git", majorVersion: 2),
    .Package(url: "https://github.com/glessard/swift-atomics.git", majorVersion: 3),
  ]
)
