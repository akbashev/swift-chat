import Distributed
import DistributedCluster
import EventSource
import Backend

distributed actor RoomPool: LifecycleWatch {

  enum Error: Swift.Error {
    case roomNotFound
  }
  
  public typealias ActorSystem = ClusterSystem

  private lazy var rooms: Set<Room> = .init()
  private var listingTask: Task<Void, Never>?
  
  distributed func findRoom(
    with info: RoomInfo,
    eventSource: EventSource<MessageInfo>
  ) async throws -> Room {
    for room in rooms {
      let roomId = try await room.getRoomInfo().id
      if info.id == roomId {
        return room
      }
    }
    return try await self.spawnRoom(
      with: info,
      eventSource: eventSource
    )
  }
  
  private func spawnRoom(
    with info: RoomInfo,
    eventSource: EventSource<MessageInfo>
  ) async throws -> Room {
    try await Room(
      actorSystem: self.actorSystem,
      roomInfo: info,
      eventSource: eventSource
    )
  }

  func terminated(actor id: ActorID) {
    guard let actor = self.rooms.first(where: { $0.id == id }) else { return }
    self.rooms.remove(actor)
  }
  
  private func findRooms() {
    guard self.listingTask == nil else {
      return self.actorSystem.log.info("Already looking for rooms")
    }
    
    self.listingTask = Task {
      for await room in await actorSystem.receptionist.listing(of: .rooms) {
        self.rooms.insert(room)
      }
    }
  }
  
  init(
    actorSystem: ClusterSystem
  ) async {
    self.actorSystem = actorSystem
    self.findRooms()
    await actorSystem
      .receptionist
      .checkIn(self, with: .roomPools)
  }
}

extension DistributedReception.Key {
  static var roomPools: DistributedReception.Key<RoomPool> { "room_pools" }
}
