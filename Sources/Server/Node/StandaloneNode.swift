import DistributedCluster
import Backend
import VirtualActor

enum StandaloneNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {
    let mainNode = await ClusterSystem("main") {
      $0.bindHost = host
      $0.bindPort = port
      $0.plugins.install(plugin: ClusterSingletonPlugin())
    }
    let roomNode = await ClusterSystem("roomNode") {
      $0.bindHost = host
      $0.bindPort = port + 1
    }
    let dbNode = await ClusterSystem("dbNode") {
      $0.bindHost = host
      $0.bindPort = port + 2
    }
    
    roomNode.cluster.join(node: mainNode.cluster.node)
    dbNode.cluster.join(node: mainNode.cluster.node)
    
    try await Self.ensureCluster(mainNode, roomNode, dbNode, within: .seconds(10))
    
    // We need references for ARC not to clean them up
    let frontend = try await FrontendNode(
      actorSystem: mainNode
    )
    let room = await VirtualNode<Room, RoomInfo>(
      actorSystem: roomNode
    )
    let databaseNode = try await DatabaseNode(
      actorSystem: dbNode
    )
    try await mainNode.terminated
  }
}
