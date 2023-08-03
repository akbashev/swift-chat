// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SimpleChat",
  platforms: [
    .macOS("13.3"),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-distributed-actors.git", branch: "main"),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "1.0.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-foundation.git", .branch("main"))
  ],
  targets: [
    .target(
      name: "Backend",
      dependencies: [
        "Models",
        "Plugins",
        "Store",
        .product(name: "DistributedCluster", package: "swift-distributed-actors"),
      ]
    ),
    .target(
      name: "Frontend",
      dependencies: [
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdFoundation", package: "hummingbird"),
        .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
        .product(name: "DistributedCluster", package: "swift-distributed-actors"),
        .product(name: "FoundationEssentials", package: "swift-foundation"),
      ]
    ),
    .target(
      name: "Models",
      dependencies: [
        .product(name: "FoundationEssentials", package: "swift-foundation"),
      ]
    ),
    .target(
      name: "Plugins"
    ),
    .executableTarget(
      name: "Server",
      dependencies: [
        "Backend",
        "Frontend",
        .product(name: "DistributedCluster", package: "swift-distributed-actors"),
      ]
    ),
    .target(
      name: "Store",
      dependencies: [
        "Models",
        .product(name: "DistributedCluster", package: "swift-distributed-actors"),
      ]
    ),
  ]
)
