import Backend
import Distributed
import DistributedCluster

distributed actor RoomPoolManager: LifecycleWatch {

  enum Error: Swift.Error {
    case roomPoolUnavailable
  }
  
  typealias ActorSystem = ClusterSystem

  private lazy var roomPools: Set<RoomPool> = .init()
  private var listingTask: Task<Void, Never>?
  
  distributed public func get() async throws -> RoomPool {
    guard let roomPool = self.roomPools.randomElement() else {
      return await RoomPool(actorSystem: self.actorSystem)
    }
    return roomPool
  }
  
  private func remove(actor id: ActorID) {
    guard let room = self.roomPools.first(where: { $0.id == id }) else { return }
    self.roomPools.remove(room)
  }
  
  func terminated(actor id: ActorID) {
    self.remove(actor: id)
  }
  
  private func findRoomPools() {
    guard self.listingTask == nil else {
      actorSystem.log.info("Already looking for room pools")
      return
    }
    
    self.listingTask = Task {
      for await roomPool in await actorSystem.receptionist.listing(of: .roomPools) {
        self.roomPools.insert(roomPool)
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
