import Distributed
import DistributedCluster
import EventSource
import Backend

/// Is it a pool? Should I call Node? Not sure...
distributed actor RoomNode {
  
  enum Error: Swift.Error {
    case noDatabaseAvailable
  }
  
  private lazy var localRooms: Set<Room> = .init()
  private var listingTask: Task<Void, Never>?
  private var databaseNodeListeningTask: Task<Void, Never>?
  private lazy var databaseNodes: Set<DatabaseNode> = .init()
  
  distributed public func spawnRoom(with info: RoomInfo) async throws -> Room {
    let room = try await Room(
      actorSystem: self.actorSystem,
      roomInfo: info,
      eventSource: self.getDatabaseNode()
        .getEventSource()
    )
    self.localRooms.insert(room)
    return room
  }
  
  init(
    actorSystem: ClusterSystem
  ) async {
    self.actorSystem = actorSystem
    self.findDatabaseNodes()
    await actorSystem
      .receptionist
      .checkIn(self, with: .roomNodes)
  }
}

extension RoomNode: LifecycleWatch {
  
  func terminated(actor id: ActorID) {
    if let dbActor = self.databaseNodes.first(where: { $0.id == id }) {
      self.databaseNodes.remove(dbActor)
    }
    // Let's just remove all local rooms for now...
    // TODO: Remove rooms which have same eventSource
    self.localRooms.removeAll()
  }

  private func findDatabaseNodes() {
    guard self.databaseNodeListeningTask == nil else {
      actorSystem.log.info("Already looking for room db nodes")
      return
    }
    
    self.databaseNodeListeningTask = Task {
      for await databaseNode in await actorSystem.receptionist.listing(of: .databaseNodes) {
        self.databaseNodes.insert(databaseNode)
        self.watchTermination(of: databaseNode)
      }
    }
  }

  private func getDatabaseNode() async throws -> DatabaseNode {
    guard let databaseNode = self.databaseNodes.randomElement() else {
      throw Error.noDatabaseAvailable
    }
    return databaseNode
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
