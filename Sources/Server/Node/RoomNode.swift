import Distributed
import DistributedCluster
import EventSource
import Backend

/// Is it a pool? Should I call Node? Not sure...
distributed actor RoomNode {
  
  enum Error: Swift.Error {
    case noDatabaseAvailable
    case noRoomAvailable
  }
  
  private lazy var rooms: [RoomInfo.ID: Room] = [:]
  
  distributed public func spawnRoom(
    with info: RoomInfo,
    databaseNode: DatabaseNode
  ) async throws -> Room {
    let room = try await Room(
      actorSystem: self.actorSystem,
      roomInfo: info,
      eventSource: databaseNode.getEventSource()
    )
    self.rooms[info.id] = room
    return room
  }
  
  distributed public func findRoom(
    with info: RoomInfo
  ) async throws -> Room {
    guard let room = self.rooms[info.id] else {
      throw Error.noRoomAvailable
    }
    return room
  }
  
  distributed public func closeRooms(
    with eventSource: EventSource<MessageInfo>
  ) async {
    var idsToClose: [RoomInfo.ID] = []
    for (key, value) in self.rooms {
      let roomEventSource = try? await value.getEventSource()
      if eventSource.id == roomEventSource?.id {
        idsToClose.append(key)
      }
    }
    for id in idsToClose {
      self.rooms.removeValue(forKey: id)
    }
  }
  
  init(
    actorSystem: ClusterSystem
  ) async {
    self.actorSystem = actorSystem
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
