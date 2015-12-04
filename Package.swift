import PackageDescription

let package = Package(
  name: "async-deferred",
  dependencies: [
    .Package(url: "https://github.com/glessard/shuffle.git", majorVersion: 1),
  ]
)
