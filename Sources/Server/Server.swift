import Distributed
import DistributedCluster
import ArgumentParser
import Foundation
import EventSource
import VirtualActor
import EventSourcing

typealias DefaultDistributedActorSystem = ClusterSystem

@main
struct Server: AsyncParsableCommand {
  
  /**
   For simplicity you can just run `StandaloneNode`, which will run all other nodes (frontend, room, database).
   
   If you want to run them seperately you need to form a cluster. To achive that—start with `seed` node first,
   in swift distributed actors there is not difference which one it should be, for simplicity it's frontend now.
   Run it with default host. After that you can run room node with other port (e.g. 2551) and db node (e.g. 2552),
   they will call `cluster.join` call join a cluster on `main` node address.
   To see configs and what's exactly happening—check `run(host: String, port: Int)` implementation of each node.
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
  @Option var host: String = "127.0.0.1"
  @Option var port: Int = 2550
  
  func run() async throws {
    let node: any Node.Type = switch self.cluster {
    case .standalone: StandaloneNode.self
    case .frontend: FrontendNode.self
    case .room: RoomNode.self
    }
    try await run(node)
  }
  
  func run(_ node: any Node.Type) async throws {
    try await node.run(host: self.host, port: self.port)
  }
}

extension ClusterSystemSettings {
  mutating func installPlugins() {
    for plugin in Server.plugins { self += plugin }
  }
}
