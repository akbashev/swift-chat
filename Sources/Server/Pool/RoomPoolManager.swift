import Backend
import Distributed
import DistributedCluster

/// Ok, why we need a manager on top of room pools? Rooms are dynamic, which means they're created when there is a connection,
/// but in order to distributed nodes on different nodes—we need one RoomPool per node.
/// Then on top of it if I've created RoomPoolManager which listens to RoomPools lifecycle on different nodes.
/// Actually still note sure about naming. **Check other frameworks and platforms on how it's managed there**.
distributed actor RoomPoolManager: LifecycleWatch {

  enum Error: Swift.Error {
    case roomPoolUnavailable
  }
    
  private lazy var roomPools: Set<RoomPool> = .init()
  private var listingTask: Task<Void, Never>?
  private var localRoomPool: RoomPool?

  distributed public func get() async throws -> RoomPool {
    guard let roomPool = self.roomPools.randomElement() else {
      return await RoomPool(actorSystem: self.actorSystem)
    }
    return roomPool
  }
  
  func terminated(actor id: DistributedCluster.ActorID) async {
    guard let room = self.roomPools.first(where: { $0.id == id }) else { return }
    self.roomPools.remove(room)
  }
  
  private func findRoomPools() {
    guard self.listingTask == nil else {
      actorSystem.log.info("Already looking for room pools")
      return
    }
    
    self.listingTask = Task {
      for await roomPool in await actorSystem.receptionist.listing(of: .roomPools) {
        self.roomPools.insert(roomPool)
        self.watchTermination(of: roomPool)
      }
    }
  }
  
  public init(
    actorSystem: ClusterSystem
  ) {
    self.actorSystem = actorSystem
    self.findRoomPools()
  }
}
