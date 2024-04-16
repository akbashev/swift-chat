import Distributed
import DistributedCluster
import ArgumentParser
import Frontend
import Foundation
import EventSource
import VirtualActor
import EventSourcing

typealias DefaultDistributedActorSystem = ClusterSystem

@main
struct Server: AsyncParsableCommand {
  
  enum Cluster: String, ExpressibleByArgument {
    case standalone
    case frontend
    case room
  }
  
  static let plugins: [any _Plugin] = [
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
