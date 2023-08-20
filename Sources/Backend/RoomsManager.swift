import Distributed
import DistributedCluster

distributed public actor RoomsManager: LifecycleWatch, ClusterSingleton {

  public enum Error: Swift.Error {
    case roomNotFound
  }
  
  public typealias ActorSystem = ClusterSystem

  private lazy var rooms: Set<Room> = .init()
  private var listingTask: Task<Void, Never>?

  distributed public func room(for id: RoomInfo.ID) async throws -> Room {
    for room in rooms {
      let roomId = try await room.getRoomInfo().id
      if id == roomId {
        return room
      }
    }
    throw Error.roomNotFound
  }
  
  distributed public func remove(actor id: ActorID) {
    guard let room = self.rooms.first(where: { $0.id == id }) else { return }
    self.rooms.remove(room)
  }
  
  distributed public func findRooms() async {
    guard self.listingTask == nil else {
      actorSystem.log.info("Already looking for users")
      return
    }
    
    self.listingTask = Task {
      for await room in await actorSystem.receptionist.listing(of: .rooms) {
        self.rooms.insert(room)
      }
    }
  }
  
  public func terminated(actor id: ActorID) async {
    self.remove(actor: id)
  }
  
  public init(
    actorSystem: ClusterSystem
  ) {
    self.actorSystem = actorSystem
  }
}
