import DistributedCluster
import Backend

enum RoomNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {
    let roomNode = await ClusterSystem("room") {
      $0.autoLeaderElection = .lowestReachable(minNumberOfMembers: 1)
      $0.bindHost = host
      $0.bindPort = port
      $0.downingStrategy = .timeout(.default)
    }
    roomNode.cluster.join(host: "127.0.0.1", port: 2550)
    try await Server.ensureCluster([roomNode], within: .seconds(10))
    let roomPool = await RoomPool(actorSystem: roomNode)
    try await roomNode.terminated
  }
}
