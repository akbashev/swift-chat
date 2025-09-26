// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var package = Package(
  name: "swift-chat",
  platforms: [
    .macOS("15.0"),
    .iOS("18.0"),
  ],
  products: [
    .library(name: "NativeApp", targets: ["NativeApp"])
  ]
)

package.dependencies += [
  // Distributed
  .package(url: "https://github.com/apple/swift-distributed-actors.git", branch: "main"),
  .package(url: "https://github.com/akbashev/cluster-virtual-actors.git", branch: "main"),
  .package(url: "https://github.com/akbashev/cluster-event-sourcing.git", branch: "main"),
  // Apple
  .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.0"),
  .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.10.0"),
  .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.8.0"),
  .package(url: "https://github.com/apple/swift-openapi-urlsession.git", from: "1.1.0"),
  .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
  // Swift-server
  .package(url: "https://github.com/swift-server/swift-openapi-hummingbird.git", from: "2.0.0"),
  // Hummingbird
  .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.16.0"),
  .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.2.0"),
  // Vapor
  .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.27.0"),
  // Pointfree.co
  .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.22.0"),
  .package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.9.0"),
]

package.targets += [
  // Modules
  .target(
    name: "Backend",
    dependencies: [
      "Models",
      "Persistence",
      .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
      .product(name: "OpenAPIHummingbird", package: "swift-openapi-hummingbird"),
      .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
      .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
      .product(name: "HummingbirdWSCompression", package: "hummingbird-websocket"),
      .product(name: "VirtualActors", package: "cluster-virtual-actors"),
      .product(name: "DistributedCluster", package: "swift-distributed-actors"),
    ],
    plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
  ),
  .target(
    name: "Client",
    dependencies: [
      "Models",
      .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
      .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
    ],
    plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
  ),
  .target(
    name: "Models",
    dependencies: [.product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")],
    plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
  ),
  .target(
    name: "Persistence",
    dependencies: [
      .product(name: "EventSourcing", package: "cluster-event-sourcing"),
      .product(name: "DistributedCluster", package: "swift-distributed-actors"),
      .product(name: "PostgresNIO", package: "postgres-nio"),
    ]
  ),

  // APPS
  .target(
    name: "NativeApp",
    dependencies: [
      "Client",
      .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      .product(name: "Dependencies", package: "swift-dependencies"),
      .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
    ],
    swiftSettings: [
      .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
      .enableUpcomingFeature("InferIsolatedConformances"),
    ]
  ),
  .executableTarget(
    name: "CLIApp",
    dependencies: [
      "Client",
      .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ],
    swiftSettings: [
      .defaultIsolation(MainActor.self),
      .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
      .enableUpcomingFeature("InferIsolatedConformances"),
    ]
  ),
  .executableTarget(
    name: "ServerApp",
    dependencies: [
      .product(name: "ArgumentParser", package: "swift-argument-parser"),
      .product(name: "Dependencies", package: "swift-dependencies"),
      .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
      "Backend",
    ]
  ),
]
