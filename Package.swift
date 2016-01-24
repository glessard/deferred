import PackageDescription

let package = Package(
  name: "deferred",
  dependencies: [
    .Package(url: "https://github.com/glessard/shuffle.git", versions: Version(1,1,0)..<Version(2,0,0)),
  ]
)
