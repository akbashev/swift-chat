import Distributed
import DistributedCluster
import ArgumentParser
import Foundation
import EventSource
import VirtualActor
import EventSourcing

typealias DefaultDistributedActorSystem = ClusterSystem

@main
struct Server: AsyncParsableCommand, Node {
  
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
  
  static let plugins: [any Plugin] = [
    ClusterSingletonPlugin(),
    ClusterJournalPlugin { _ in
      MemoryEventStore()
    },
    ClusterVirtualActorsPlugin()
  ]
  
  @Argument var cluster: Cluster
  @Option var host: String = Server.defaultHost
  @Option var port: Int = Server.defaultPort
  var name: String {
    self.cluster.rawValue
  }
  
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
          host: Server.defaultHost,
          port: Server.defaultPort
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
    for plugin in Server.plugins { self += plugin }
  }
}

extension Server {
  static let defaultHost: String = "127.0.0.1"
  static let defaultPort: Int = 2550
}
