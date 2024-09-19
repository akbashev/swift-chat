import Distributed
import DistributedCluster

typealias DefaultDistributedActorSystem = ClusterSystem

// Internal singleton to handle nodes
distributed actor VirtualActorFactory: LifecycleWatch, ClusterSingleton {
  public enum Error: Swift.Error {
    case noNodesAvailable
    case noActorsAvailable
  }
  
  private lazy var virtualNodes: Set<VirtualNode> = .init()
  private var listeningTask: Task<Void, Never>?

  func terminated(actor id: ActorID) async {
    guard let virtualNode = self.virtualNodes.first(where: { $0.id == id }) else { return }
    try? await virtualNode.removeAll()
    self.virtualNodes.remove(virtualNode)
  }
  
  func findVirtualNodes() {
    guard self.listeningTask == nil else {
      actorSystem.log.info("Already looking for nodes")
      return
    }
    
    self.listeningTask = Task {
      for await virtualNode in await actorSystem.receptionist.listing(of: VirtualNode.key) {
        self.virtualNodes.insert(virtualNode)
        self.watchTermination(of: virtualNode)
      }
    }
  }
  
  /// - Parameters:
  /// - id—external (not system) id of an actor.
  /// - dependency—only needed when spawning an actor.
  distributed func get<A: VirtualActor>(id: VirtualID) async throws -> A {
    for virtualNode in virtualNodes {
      if let actor: A = try? await virtualNode.find(id: id) {
        return actor
      }
    }
    throw Error.noActorsAvailable
  }
  
  distributed func getNode() async throws -> VirtualNode {
    // TODO: Round robin at least
    guard let node = self.virtualNodes.randomElement() else {
      // There should be always a node (at least local node), if not—something sus
      throw Error.noNodesAvailable
    }
    return node
  }
  
  /// Actors should be cleaned automatically, but for now unfortunately manual cleaning.
  distributed func close(
    with id: ClusterSystem.ActorID
  ) async {
    await withTaskGroup(of: Void.self) { [virtualNodes] group in
      for virtualNode in virtualNodes {
        group.addTask {
          try? await virtualNode.close(with: id)
        }
      }
    }
  }
  
  /// - Parameters:
  ///  - spawn—definining how an actor should be created.
  ///  Local node is created while initialising a factory.
  init(
    actorSystem: ClusterSystem
  ) async {
    self.actorSystem = actorSystem
    self.findVirtualNodes()
  }
}
