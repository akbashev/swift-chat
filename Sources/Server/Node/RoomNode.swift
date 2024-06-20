import DistributedCluster
import VirtualActor
import Backend
import EventSource

enum RoomNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {
    let roomNode = await ClusterSystem("room") {
      $0.bindHost = host
      $0.bindPort = port
      $0.installPlugins()
    }
    roomNode.cluster.join(host: "127.0.0.1", port: 2550) // <- here should be `seed` host and port
    try await Self.ensureCluster(roomNode, within: .seconds(10))
    let node = await VirtualNode(
      actorSystem: roomNode,
      spawner: RoomSpawner()
    )
    try await roomNode.terminated
  }
}

struct RoomSpawner: VirtualActorSpawner {
  
  enum Error: Swift.Error {
    case unsupportedType
  }
  
  func spawn<A: VirtualActor, D: VirtualActorDependency>(
    with actorSystem: DistributedCluster.ClusterSystem,
    id: VirtualID,
    dependency: D
  ) async throws -> A {
    guard let dependency = dependency as? Room.Info else {
      throw Error.unsupportedType
    }
    guard let room = await Room(
      actorSystem: actorSystem,
      roomInfo: dependency
    ) as? A else {
      throw Error.unsupportedType
    }
    return room
  }
}
