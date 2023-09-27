// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swift-chat",
  platforms: [
    .macOS("13.3"),
    .iOS("16.4"),
  ],
  products: [
      .library(name: "App", targets: ["App"])
  ],
  dependencies: [
    // Apple
    .package(url: "https://github.com/apple/swift-distributed-actors.git", branch: "main"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-foundation.git", branch: "main"),
    // Hummingbird
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "1.0.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "1.0.0"),
    // Vapor
    .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.18.0"),
    // Pointfreeco
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "App",
      dependencies: [
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "Dependencies", package: "swift-dependencies")
      ]
    ),
    .target(
      name: "Backend",
      dependencies: [
        "EventSource",
        .product(name: "DistributedCluster", package: "swift-distributed-actors"),
        .product(name: "FoundationEssentials", package: "swift-foundation"),
      ]
    ),
    .target(
      name: "EventSource",
      dependencies: [
        .product(name: "DistributedCluster", package: "swift-distributed-actors"),
        .product(name: "FoundationEssentials", package: "swift-foundation"),
        "Postgres",
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
      name: "Persistence",
      dependencies: [
        .product(name: "DistributedCluster", package: "swift-distributed-actors"),
        .product(name: "FoundationEssentials", package: "swift-foundation"),
        "Postgres",
      ]
    ),
    .target(
      name: "Postgres",
      dependencies: [
        .product(name: "FoundationEssentials", package: "swift-foundation"),
        .product(name: "PostgresNIO", package: "postgres-nio"),
      ]
    ),
    .executableTarget(
      name: "Server",
      dependencies: [
        "Backend",
        "Frontend",
        "Persistence",
      ]
    ),
  ]
)
