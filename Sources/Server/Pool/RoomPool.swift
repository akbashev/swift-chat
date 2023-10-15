import Distributed
import DistributedCluster
import EventSource
import Backend

/**
 Not actually pool, I guess? Just started to write some custom pool and name sticks now.
 Not sure what is proper name.
 */
distributed actor RoomPool: LifecycleWatch {

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
    return try await self.spawn(
      with: info,
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
        self.watchTermination(of: room)
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

extension RoomPool {
  private func spawn(
    with info: RoomInfo,
    eventSource: EventSource<MessageInfo>
  ) async throws -> Room {
    try await Room(
      actorSystem: self.actorSystem,
      roomInfo: info,
      eventSource: eventSource
    )
  }
}
