import Distributed
import DistributedCluster

distributed public actor VirtualNode {
  
  public enum Error: Swift.Error {
    case noActorAvailable
  }
  
  private lazy var virtualActors: [VirtualID: any VirtualActor] = [:]
  private let spawner: VirtualActorSpawner

  distributed func register<A: VirtualActor>(actor: A, with id: VirtualID) {
    self.virtualActors[id] = actor
  }
  
  distributed public func find<A: VirtualActor>(id: VirtualID) async throws -> A {
    guard let actor = self.virtualActors[id] as? A else {
      throw Error.noActorAvailable
    }
    return actor
  }
  
  distributed public func close(
    with id: ClusterSystem.ActorID
  ) async {
    let value = self.virtualActors.first(where: { $0.value.id == id })
    if let virtualId = value?.key {
      self.virtualActors.removeValue(forKey: virtualId)
    }
  }
  
  distributed public func removeAll() {
    self.virtualActors.removeAll()
  }
  
  distributed public func spawnActor<A: VirtualActor, D: VirtualActorDependency>(with id: VirtualID, dependency: D) async throws -> A {
    let actor: A = try await self.spawner.spawn(
      with: self.actorSystem,
      id: id,
      dependency: dependency
    )
    self.virtualActors[id] = actor
    return actor
  }
  
  public init(
    actorSystem: ClusterSystem,
    spawner: VirtualActorSpawner
  ) async {
    self.actorSystem = actorSystem
    self.spawner = spawner
    await actorSystem
      .receptionist
      .checkIn(self, with: Self.key)
  }
}

extension VirtualNode {
  static var key: DistributedReception.Key<VirtualNode> { "virtual_nodes" }
}

public protocol VirtualActorSpawner: Codable, Sendable {
  func spawn<A: VirtualActor, D: VirtualActorDependency>(with actorSystem: ClusterSystem, id: VirtualID, dependency: D) async throws -> A
}
