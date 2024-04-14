import DistributedCluster
import Backend
import VirtualActor
import EventSource

enum StandaloneNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {    
    let mainNode = await ClusterSystem("main") {
      $0.bindHost = host
      $0.bindPort = port
      $0.plugins.install(plugin: ClusterSingletonPlugin())
      $0.plugins.install(
        plugin: ClusterJournalPlugin {
          MemoryEventStore(actorSystem: $0)
        }
      )
    }
    let roomNode = await ClusterSystem("roomNode") {
      $0.bindHost = host
      $0.bindPort = port + 1
    }
    roomNode.cluster.join(node: mainNode.cluster.node)
    
    try await Self.ensureCluster(mainNode, roomNode, within: .seconds(10))
    
    // We need references for ARC not to clean them up
    let frontend = try await FrontendNode(
      actorSystem: mainNode
    )
    let room = await VirtualNode<Room, RoomInfo>(
      actorSystem: roomNode
    )
    try await mainNode.terminated
  }
}
