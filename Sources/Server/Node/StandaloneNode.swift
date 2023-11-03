import DistributedCluster
import Backend
import VirtualActor

enum StandaloneNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {
    /// System names are `a`, `b`, `c` in alphabetic order right now due to ClusterEndpoint Comparable current implementation.
    let actorSystem = await ClusterSystem("a") {
      $0.bindHost = host
      $0.bindPort = port
      $0.plugins.install(plugin: ClusterSingletonPlugin())
    }
    let roomNode = await ClusterSystem("b") {
      $0.bindHost = host
      $0.bindPort = port + 1
    }
    let dbNode = await ClusterSystem("c") {
      $0.bindHost = host
      $0.bindPort = port + 2
    }
    
    roomNode.cluster.join(node: actorSystem.cluster.node)
    dbNode.cluster.join(node: actorSystem.cluster.node)
    try await Self.ensureCluster(actorSystem, roomNode, dbNode, within: .seconds(10))
    
    // We need references for ARC not to clean them up
    let frontend = try await FrontendNode(
      actorSystem: actorSystem
    )
    let room = await VirtualNode<Room, RoomInfo>(
      actorSystem: roomNode
    )
    let databaseNode = try await DatabaseNode(
      actorSystem: dbNode
    )
    try await actorSystem.terminated
  }
}
