import Distributed
import DistributedCluster

distributed public actor VirtualNode {
  
  public enum Error: Swift.Error {
    case noActorAvailable
  }
  
  private lazy var virtualActors: [VirtualID: any VirtualActor] = [:]
  
  distributed func register<A: VirtualActor>(actor: A) {
    guard let id = actor.metadata.virtualID else {
      fatalError("Virtual actor ID is not defined, please do it by defining an @ActorID.Metadata(\\.virtualID) property")
    }
    self.virtualActors[id] = actor
  }
  
  distributed public func find<A: VirtualActor>(id: VirtualID) async throws -> A {
    guard let actor = self.virtualActors[id] as? A else {
      throw Error.noActorAvailable
    }
    return actor
  }
  
  distributed public func close(
    with id: VirtualID
  ) async {
    self.virtualActors.removeValue(forKey: id)
  }
  
  public init(
    actorSystem: ClusterSystem
  ) async {
    self.actorSystem = actorSystem
    await actorSystem
      .receptionist
      .checkIn(self, with: Self.key)
  }
}

extension VirtualNode {
  static var key: DistributedReception.Key<VirtualNode> { "virtual_nodes" }
}
