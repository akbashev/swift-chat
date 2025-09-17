import ArgumentParser
import Distributed
import DistributedCluster
import EventSourcing
import Foundation
import Hummingbird
import Persistence
import VirtualActors

typealias DefaultDistributedActorSystem = ClusterSystem

@main
struct App: AsyncParsableCommand {

  /**
   For simplicity you can just run `standalone` node, which will run all other nodes (frontend, room) + database.
  
   If you want to run them seperately you need to form a cluster. To achive that—start with some first one,
   in swift distributed actors there is not difference which one it should be, for simplicity it's `frontend` now.
   Run it with default host. After that you can run room node with other port (e.g. 2551) and etc.,
   they will call `cluster.join` to form a cluster with default host node address.
   */
  enum Node: String, ExpressibleByArgument {
    case daemon
    case standalone
    case frontend
    case room
  }

  @Argument var node: Node
  @Option var host: String = App.defaultHost
  @Option var port: Int = App.defaultPort
  var name: String {
    self.node.rawValue
  }

  func run() async throws {
    switch self.node {
    case .daemon:
      try await self.daemon()
    case .frontend:
      try await self.frontend()
    case .room:
      try await self.room()
    case .standalone:
      try await withThrowingDiscardingTaskGroup { group in
        group.addTask { try await self.daemon() }
        group.addTask { try await self.frontend() }
        group.addTask { try await self.room() }
      }
    }
  }
}

extension App {
  func daemon() async throws {
    try await Daemon().run()
  }

  func frontend() async throws {
    let plugins: [any Plugin] = [
      ClusterSingletonPlugin(),
      ClusterVirtualActorsPlugin(),
      ClusterJournalPlugin { _ in MemoryEventStore() },
    ]
    let clusterSystem = await ClusterSystem(self.name) {
      $0.bindHost = self.host
      $0.bindPort = self.port
      $0.discovery = .clusterd
      for plugin in plugins {
        $0.plugins.install(plugin: plugin)
      }
    }
    try await Frontend(
      clusterSystem: clusterSystem
    ).run()
  }

  func room() async throws {
    // TODO: Need to figure out how different plugins, especially event store, behave when you have multiple systems.
    //    let env = Environment()
    //    let config = try PostgresConfig(
    //      host: self.host,
    //      environment: env
    //    ).generate()
    //    let store = try await PostgresEventStore(
    //      connection: .connect(
    //        configuration: config,
    //        id: 2,
    //        logger: .init(label: "event-source-postgres-logger")
    //      )
    //    )
    let plugins: [any Plugin] = [
      ClusterSingletonPlugin(),
      ClusterVirtualActorsPlugin(),
      ClusterJournalPlugin { _ in MemoryEventStore() },
    ]
    let roomNode = await ClusterSystem(self.name) {
      $0.bindHost = self.host
      $0.bindPort = self.port + 1
      $0.discovery = .clusterd
      for plugin in plugins {
        $0.plugins.install(plugin: plugin)
      }
    }
    try await Room(
      clusterSystem: roomNode
    ).run()
  }
}

extension App {
  static let defaultHost: String = "127.0.0.1"
  static let defaultPort: Int = 2550
}
