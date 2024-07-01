import DistributedCluster
import VirtualActor
import Backend
import EventSource
import ServiceLifecycle

struct Backend: Service {
  
  let clusterSystem: ClusterSystem
  let host: Cluster.Endpoint
  
  func run() async throws {
    self.clusterSystem.cluster.join(endpoint: host)
    try await self.clusterSystem.cluster.joined(within: .seconds(10))
    let virtualNode = await VirtualNode(
      actorSystem: self.clusterSystem,
      spawner: RoomSpawner()
    )
    try await virtualNode.actorSystem.terminated
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
