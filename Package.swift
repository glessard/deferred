import PackageDescription

let package = Package(
  name: "deferred",
  dependencies: [
    .Package(url: "https://github.com/glessard/shuffle.git", majorVersion: 2),
  ]
)
