import Backend
import Distributed
import DistributedCluster

/**
 Not actually observer, I guess? Not sure what is proper name.
 */
distributed actor RoomNodeObserver: LifecycleWatch {

  enum Error: Swift.Error {
    case roomNodeUnavailable
  }
    
  private lazy var roomNodes: Set<RoomNode> = .init()
  private var listingTask: Task<Void, Never>?

  distributed public func get() async throws -> RoomNode {
    guard let roomPool = self.roomNodes.randomElement() else {
      return await RoomNode(actorSystem: self.actorSystem)
    }
    return roomPool
  }
  
  func terminated(actor id: DistributedCluster.ActorID) async {
    guard let roomNode = self.roomNodes.first(where: { $0.id == id }) else { return }
    self.roomNodes.remove(roomNode)
  }
  
  private func findRoomNodes() {
    guard self.listingTask == nil else {
      actorSystem.log.info("Already looking for room pools")
      return
    }
    
    self.listingTask = Task {
      for await roomNode in await actorSystem.receptionist.listing(of: .roomNodes) {
        self.roomNodes.insert(roomNode)
        self.watchTermination(of: roomNode)
      }
    }
  }
  
  public init(
    actorSystem: ClusterSystem
  ) {
    self.actorSystem = actorSystem
    self.findRoomNodes()
  }
}
