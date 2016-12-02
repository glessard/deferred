import PackageDescription

let package = Package(
  name: "deferred",
  targets: [
    Target(name: "deferred", dependencies: ["utilities"]),
    Target(name: "utilities"),
  ],
  dependencies: [
    .Package(url: "https://github.com/glessard/shuffle.git", majorVersion: 2),
    .Package(url: "https://github.com/glessard/syncprint.git", majorVersion: 2)
  ]
)
