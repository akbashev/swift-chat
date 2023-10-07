import DistributedCluster
import Persistence
import EventSource

enum DatabaseNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {
    let dbNode = await ClusterSystem("database") {
      $0.autoLeaderElection = .lowestReachable(minNumberOfMembers: 1)
      $0.bindHost = host
      $0.bindPort = port
      $0.downingStrategy = .timeout(.default)
    }
    
    dbNode.cluster.join(host: "127.0.0.1", port: 2550)
    try await Server.ensureCluster([dbNode], within: .seconds(10))
    
    /// We need references otherwise PostgresConnection closes. Maybe there is a workaround? 🤔
    let persistance = try await PersistencePool.spawnPersistence(clusterSystem: dbNode)
    let eventSource = try await EventSourcePool.spawnEventSource(clusterSystem: dbNode)
    
    try await dbNode.terminated
  }
}
