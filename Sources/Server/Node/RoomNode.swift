import DistributedCluster
import VirtualActor
import Backend

enum RoomNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {
    let roomNode = await ClusterSystem("room") {
      $0.bindHost = host
      $0.bindPort = port
    }
    roomNode.cluster.join(host: "127.0.0.1", port: 2550)
    try await Self.ensureCluster(roomNode, within: .seconds(10))
    let roomPool = await VirtualNode<Room, RoomInfo>(actorSystem: roomNode)
    try await roomNode.terminated
  }
}
