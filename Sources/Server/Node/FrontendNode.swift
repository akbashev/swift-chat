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
 
/// Don't look quite elegant and not sure if it's a correct way of handling things.
/// Also, how do you load balance HBApplication? 🤔
/// How does this work in other frameworks? 🤔
distributed actor FrontendNode: LifecycleWatch {
  
  enum Error: Swift.Error {
    case noConnection
  }
  
  private lazy var databaseNodes: Set<DatabaseNode> = .init()
  private lazy var roomNodes: Set<RoomNode> = .init()
  private var wsConnections: [UUID: WebsocketConnection] = [:]
  /// [DatabaseNode.ID: HttpConnection] dict here. HttpConnection needs persistence.
  private var httpConnections: [DistributedCluster.ActorID: HttpConnection] = [:]
  
  private var wsConnectionListeningTask: Task<Void, Never>?
  private var databaseNodeListeningTask: Task<Void, Never>?
  private var roomNodeListeningTask: Task<Void, Never>?
  
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
    self.findDatabaseNodes()
    try app.start()
  }
  
  
  func terminated(actor id: DistributedCluster.ActorID) async {
    if let roomNode = self.roomNodes.first(where: { $0.id == id }) {
      self.roomNodes.remove(roomNode)
    }
    if let databaseNode = self.databaseNodes.first(where: { $0.id == id }) {
      self.httpConnections[id] = .none
      self.databaseNodes.remove(databaseNode)
    }
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
      await self.wsConnections[info.userId]?.close()
      self.wsConnections[info.userId] = .none
    case .connect(let info):
      let roomNode = await self.getRoomNode()
      let databaseNode = try await self.getDatabaseNode()
      self.wsConnections[info.userId] = try await WebsocketConnection(
        actorSystem: self.actorSystem,
        persistence: databaseNode.getPersistence(),
        eventSource: databaseNode.getEventSource(),
        roomNode: roomNode,
        info: info
      )
    }
  }
}

extension FrontendNode {
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
  
  private func getDatabaseNode() async throws -> DatabaseNode {
    guard let databaseNode = self.databaseNodes.randomElement() else {
      return try await spawnDatabaseNode()
    }
    return databaseNode
  }
  
  private func spawnDatabaseNode() async throws -> DatabaseNode {
    try await DatabaseNode(
      actorSystem: self.actorSystem
    )
  }
}

extension FrontendNode {
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
  
  private func getRoomNode() async -> RoomNode {
    guard let roomNode = self.roomNodes.randomElement() else {
      return await spawnRoomNode()
    }
    return roomNode
  }
  
  private func spawnRoomNode() async -> RoomNode {
    await RoomNode(
      actorSystem: self.actorSystem
    )
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
