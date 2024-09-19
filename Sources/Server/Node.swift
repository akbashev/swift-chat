import Distributed
import DistributedCluster
import ArgumentParser
import Foundation
import EventSource
import VirtualActor
import EventSourcing

typealias DefaultDistributedActorSystem = ClusterSystem

@main
struct Node: AsyncParsableCommand {
  
  /**
   For simplicity you can just run `standalone` node, which will run all other nodes (frontend, room) + database.
   
   If you want to run them seperately you need to form a cluster. To achive that—start with some first one,
   in swift distributed actors there is not difference which one it should be, for simplicity it's `frontend` now.
   Run it with default host. After that you can run room node with other port (e.g. 2551) and etc.,
   they will call `cluster.join` to form a cluster with default host node address.
   */
  enum Cluster: String, ExpressibleByArgument {
    case standalone
    case frontend
    case room
  }
  
  @Argument var cluster: Cluster
  @Option var host: String = Node.defaultHost
  @Option var port: Int = Node.defaultPort
  var name: String {
    self.cluster.rawValue
  }
  
  func run() async throws {
    let clusterSystem = await ClusterSystem(self.name) {
      $0.bindHost = host
      $0.bindPort = port
      $0.installPlugins()
    }
    try await self.run(
      on: clusterSystem
    )
  }
  
}

/// Logic to decide how to run each node cluster system
extension Node {
  func run(on clusterSystem: ClusterSystem) async throws {
    switch self.cluster {
    case .frontend:
      let frontend = Frontend(
        clusterSystem: clusterSystem
      )
      return try await frontend.run()
    case .room:
      let backend = Backend(
        clusterSystem: clusterSystem,
        host: .init(
          host: Node.defaultHost,
          port: Node.defaultPort
        )
      )
      return try await backend.run()
    case .standalone:
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          let frontend = Frontend(
            clusterSystem: clusterSystem
          )
          return try await frontend.run()
        }
        group.addTask {
          let endpoint = clusterSystem.cluster.endpoint
          let roomNode = await ClusterSystem("room") {
            $0.bindHost = endpoint.host
            $0.bindPort = endpoint.port + 1
            $0.installPlugins()
          }
          let backend = Backend(
            clusterSystem: roomNode,
            host: endpoint
          )
          return try await backend.run()
        }
        return try await group
          .waitForAll()
      }
    }
  }
}

extension ClusterSystemSettings {
  mutating func installPlugins() {
      let plugins: [any Plugin] = [
        ClusterSingletonPlugin(),
        ClusterJournalPlugin { _ in
            MemoryEventStore()
        },
        ClusterVirtualActorsPlugin()
      ]
    for plugin in plugins { self += plugin }
  }
}

extension Node {
  static let defaultHost: String = "127.0.0.1"
  static let defaultPort: Int = 2550
}
