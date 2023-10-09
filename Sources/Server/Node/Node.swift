/// Not sure if I need it, but will put it for now.
protocol Node {
  static func run(host: String, port: Int) async throws 
}

import DistributedCluster

extension Node {
  /// Waiting for all the clusters to be up
  static func ensureCluster(_ systems: ClusterSystem..., within: Duration) async throws {
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
