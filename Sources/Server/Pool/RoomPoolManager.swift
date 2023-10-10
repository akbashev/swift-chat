import Backend
import Distributed
import DistributedCluster

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
