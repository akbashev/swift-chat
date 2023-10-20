import HummingbirdWSCore
import HummingbirdWebSocket
import HummingbirdFoundation
import FoundationEssentials
import Frontend
import Backend
import Persistence
import EventSource
import Distributed
import DistributedCluster
import PostgresNIO
 
/// Doesn't look quite elegant and not sure if it's a correct way of handling things.
/// Also, how do you load balance HBApplication? 🤔
/// How does this work in other frameworks? 🤔
distributed actor FrontendNode {
  
  enum Error: Swift.Error {
    case noConnection
  }
  
  private lazy var databaseNodes: Set<DatabaseNode> = .init()
  private lazy var roomNodes: Set<RoomNode> = .init()
  private lazy var rooms: Set<Room> = .init()
  private var wsConnections: [UUID: WebsocketConnection] = [:]
  /// [DatabaseNode.ID: HttpConnection] dict here. HttpConnection needs persistence.
  private var httpConnections: [DistributedCluster.ActorID: HttpConnection] = [:]
  
  private var wsConnectionListeningTask: Task<Void, Never>?
  private var databaseNodeListeningTask: Task<Void, Never>?
  private var roomNodeListeningTask: Task<Void, Never>?
  private var roomsListeningTask: Task<Void, Never>?

  /// We need references otherwise PostgresConnection closes. Maybe there is a workaround? 🤔
  // TODO: How do I clean up them when no more needed?
  private var localDatabaseNode: DatabaseNode?
  private var localRoomNode: RoomNode?
  
  init(
    actorSystem: ClusterSystem,
    app: HBApplication
  ) throws {
    self.actorSystem = actorSystem
    app.ws.addUpgrade()
    app.ws.add(middleware: HBLogRequestsMiddleware(.info))
    let events = WebsocketApi.configure(builder: app.ws)
    self.listenForConnections(events: events)
    self.findRoomNodes()
    self.findRooms()
    self.findDatabaseNodes()
    try app.start()
  }
}

extension FrontendNode {
  
  private func listenForConnections(events: AsyncStream<WebsocketApi.Event>) {
    self.wsConnectionListeningTask = Task {
      for await event in events {
        try? await self.handle(event: event)
      }
    }
  }
  
  private func handle(event: WebsocketApi.Event) async throws {
    switch event {
    case .close(let info):
      self.closeConnectionFor(userId: info.userId)
    case .connect(let info):
      let roomNode = await self.getRoomNode()
      let persistence = try await self.getDatabaseNode().getPersistence()
      let room = try await self.findRoom(with: info)
      let userModel = try await persistence.getUser(id: info.userId)
      // userId key won't work with mulptiple devices
      // TODO: Create another key
      self.wsConnections[info.userId] = try await WebsocketConnection(
        actorSystem: self.actorSystem,
        ws: info.ws,
        persistence: persistence,
        room: room,
        userModel: userModel
      )
    }
  }
  
  private func closeConnectionFor(userId: UUID) {
    let connection = self.wsConnections[userId]
    self.wsConnections[userId] = .none
    Task { await connection?.close() }
  }
  
  private func checkConnections(with id: DistributedCluster.ActorID) {
//    for (userId, connection) in self.wsConnections {
//      let connectionInfo = connection.info
//      if connectionInfo.databaseNodeId == id {
//        self.closeConnectionFor(userId: userId)
//      }
//    }
  }
  
  private func findRoom(
    with info: WebsocketApi.Event.Info
  ) async throws -> Room {
    let databaseNode = try await self.getDatabaseNode()
    let persistence = try await databaseNode.getPersistence()
    
    let roomModel = try await persistence.getRoom(id: info.roomId)
    let roomInfo = RoomInfo(
      id: roomModel.id,
      name: roomModel.name,
      description: roomModel.description
    )

    for room in self.rooms {
      let roomId = try await room.getRoomInfo().id
      if roomInfo.id == roomId {
        return room
      }
    }
    
    let roomNode = await self.getRoomNode()

    let userModel = try await persistence.getUser(id: info.userId)
    return try await roomNode.spawnRoom(
      with: roomInfo
    )
  }
}

extension FrontendNode: LifecycleWatch {
  
  func terminated(actor id: DistributedCluster.ActorID) {
    if let roomNode = self.roomNodes.first(where: { $0.id == id }) {
      self.roomNodes.remove(roomNode)
    }
    if let databaseNode = self.databaseNodes.first(where: { $0.id == id }) {
      self.httpConnections[id] = .none
      self.databaseNodes.remove(databaseNode)
    }
    if let actor = self.rooms.first(where: { $0.id == id }) {
      self.rooms.remove(actor)
    }
    
    self.checkConnections(with: id)
  }
  
  private func findDatabaseNodes() {
    guard self.databaseNodeListeningTask == nil else {
      actorSystem.log.info("Already looking for room pools")
      return
    }
    
    self.databaseNodeListeningTask = Task {
      for await databaseNode in await actorSystem.receptionist.listing(of: .databaseNodes) {
        self.databaseNodes.insert(databaseNode)
        self.watchTermination(of: databaseNode)
        
        self.httpConnections[databaseNode.id] = try? await spawnConnection(for: databaseNode)
      }
    }
  }
  
  private func findRoomNodes() {
    guard self.roomNodeListeningTask == nil else {
      actorSystem.log.info("Already looking for room nodes")
      return
    }
    
    self.roomNodeListeningTask = Task {
      for await roomNode in await actorSystem.receptionist.listing(of: .roomNodes) {
        self.roomNodes.insert(roomNode)
        self.watchTermination(of: roomNode)
      }
    }
  }
  
  private func getDatabaseNode() async throws -> DatabaseNode {
    guard let databaseNode = self.databaseNodes.randomElement() else {
      return try await spawnDatabaseNode()
    }
    return databaseNode
  }
  
  private func spawnDatabaseNode() async throws -> DatabaseNode {
    if let localDatabaseNode { return localDatabaseNode }
    let databaseNode = try await DatabaseNode(
      actorSystem: self.actorSystem
    )
    self.localDatabaseNode = databaseNode
    return databaseNode
  }

  
  private func getRoomNode() async -> RoomNode {
    guard let roomNode = self.roomNodes.randomElement() else {
      return await spawnRoomNode()
    }
    return roomNode
  }
  
  private func spawnRoomNode() async -> RoomNode {
    if let localRoomNode { return localRoomNode }
    let roomNode = await RoomNode(
      actorSystem: self.actorSystem
    )
    self.localRoomNode = roomNode
    return roomNode
  }
  
  private func findRooms() {
    guard self.roomsListeningTask == nil else {
      return self.actorSystem.log.info("Already looking for rooms")
    }
    
    self.roomsListeningTask = Task {
      for await room in await actorSystem.receptionist.listing(of: .rooms) {
        self.rooms.insert(room)
        self.watchTermination(of: room)
      }
    }
  }
  
}

extension FrontendNode: RestApi {
  
  distributed func createUser(_ request: Frontend.CreateUserRequest) async throws -> Frontend.UserResponse {
    try await self.getConnection()
      .createUser(request)
  }
  
  distributed func creteRoom(_ request: Frontend.CreateRoomRequest) async throws -> Frontend.RoomResponse {
    try await self.getConnection()
      .creteRoom(request)
  }
  
  distributed func searchRoom(_ request: Frontend.SearchRoomRequest) async throws -> [Frontend.RoomResponse] {
    try await self.getConnection()
      .searchRoom(request)
  }

  private func getConnection() async throws -> HttpConnection {
    guard let worker = self.httpConnections.values.shuffled().first else {
      actorSystem.log.error("No workers to submit job to. Workers: \(self.httpConnections)")
      return try await spawnConnection(for: self.getDatabaseNode())
    }
    return worker
  }
  
  private func spawnConnection(for databaseNode: DatabaseNode) async throws -> HttpConnection {
    let worker = try await HttpConnection(
      persistence: databaseNode.getPersistence()
    )
    self.httpConnections[databaseNode.id] = worker
    return worker
  }
}

extension FrontendNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {
    let actorSystem = await ClusterSystem("frontend") {
      $0.bindHost = host
      $0.bindPort = port
    }
    let app = HBApplication(
      configuration: .init(
        address: .hostname(
          host,
          port: 8080
        ),
        serverName: "frontend"
      )
    )

    app.encoder = JSONEncoder()
    app.decoder = JSONDecoder()
    
    let frontend = try Self(
      actorSystem: actorSystem,
      app: app
    )
    frontend
      .configure(
        router: app.router
      )
    
    try await actorSystem.terminated
  }
}
