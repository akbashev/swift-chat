import Distributed
import DistributedCluster
import ArgumentParser

@main
struct Server: AsyncParsableCommand {
  
  @Argument var cluster: Cluster
  @Option var host: String = "127.0.0.1"
  @Option var port: Int = 2550
  
  enum Cluster: String, ExpressibleByArgument {
    case main
    case room
    case database
  }
  
  func run() async throws {
    switch self.cluster {
    case .main:
      try await MainNode.run(
        host: self.host,
        port: self.port
      )
    case .room:
      try await RoomNode.run(
        host: self.host,
        port: self.port
      )
    case .database:
      try await DatabaseNode.run(
        host: self.host,
        port: self.port
      )
    }
  }
  
  /// Waiting for all the clusters to be up
  static func ensureCluster(_ systems: [ClusterSystem], within: Duration) async throws {
    let nodes = Set(systems.map(\.settings.bindNode))
    
    try await withThrowingTaskGroup(of: Void.self) { group in
      for system in systems {
        group.addTask {
          try await system.cluster.waitFor(nodes, .up, within: within)
        }
      }
      // loop explicitly to propagagte any error that might have been thrown
      for try await _ in group {
        
      }
    }
  }
}
