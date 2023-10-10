import Distributed
import DistributedCluster
import ArgumentParser
import Frontend
import FoundationEssentials

typealias DefaultDistributedActorSystem = ClusterSystem

@main
struct Server: AsyncParsableCommand {
  
  enum Cluster: String, ExpressibleByArgument {
    case main
    case room
    case database
  }
  
  @Argument var cluster: Cluster
  @Option var host: String = "127.0.0.1"
  @Option var port: Int = 2550
  
  func run() async throws {
    try await switch self.cluster {
    case .main: run(Main.self)
    case .room: run(RoomNode.self)
    case .database: run(Database.self)
    }
  }
  
  func run(_ node: any Node.Type) async throws {
    try await node.run(host: self.host, port: self.port)
  }
}
