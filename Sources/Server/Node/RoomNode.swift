import Distributed
import DistributedCluster
import EventSource
import Backend

/// Is it a pool? Should I call Node? Not sure...
distributed actor RoomNode: LifecycleWatch {
  
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
      .checkIn(self, with: .roomNodes)
  }
}
 
extension RoomNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {
    let roomNode = await ClusterSystem("room") {
      $0.downingStrategy = .timeout(.serverDefault)
      $0.bindHost = host
      $0.bindPort = port
    }
    roomNode.cluster.join(host: "127.0.0.1", port: 2550)
    try await Self.ensureCluster(roomNode, within: .seconds(10))
    let roomPool = await Self(actorSystem: roomNode)
    try await roomNode.terminated
  }
}

extension DistributedReception.Key {
  static var roomNodes: DistributedReception.Key<RoomNode> { "room_nodes" }
}

extension RoomNode {
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
