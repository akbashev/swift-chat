import HummingbirdWSCore
import HummingbirdWebSocket
import HummingbirdFoundation
import Foundation
import Frontend
import Backend
import Persistence
import EventSource
import Distributed
import DistributedCluster
import PostgresNIO
import VirtualActor

/// Doesn't look quite elegant and not sure if it's a correct way of handling things.
/// Also, how do you load balance HBApplication? 🤔
/// How does this work in other frameworks? 🤔
distributed actor FrontendNode {
  
  enum Error: Swift.Error {
    case noConnection
    case noDatabaseAvailable
  }
  
  private lazy var databaseNodes: Set<DatabaseNode> = .init()
  private var wsConnections: [UUID: WebsocketConnection] = [:]
  /// [DatabaseNode.ID: HttpConnection] dict here. HttpConnection needs persistence.
  private var httpConnections: [DistributedCluster.ActorID: HttpConnection] = [:]
  
  private var wsConnectionListeningTask: Task<Void, Never>?
  private var databaseNodeListeningTask: Task<Void, Never>?
  private let roomFactory: VirtualActorFactory<Room, RoomInfo, EventSource<MessageInfo>>
  private lazy var app = HBApplication(
    configuration: .init(
      address: .hostname(
        self.actorSystem.cluster.node.host,
        port: 8080
      ),
      serverName: "frontend"
    )
  )
  /// We need references otherwise PostgresConnection closes. Maybe there is a workaround? 🤔
  // TODO: How do I clean up them when no more needed?
  private var localDatabaseNode: DatabaseNode?
  private var localRoomNode: RoomNode?
  
  init(
    actorSystem: ClusterSystem
  ) async throws {
    self.actorSystem = actorSystem
    self.roomFactory = try await actorSystem.singleton.host(name: "roomFactory") { actorSystem in
      await .init(
        actorSystem: actorSystem,
        spawn: { actorSystem, info, eventSource in
          guard let eventSource else {
            throw Error.noDatabaseAvailable
          }
          return try await Room(
            actorSystem: actorSystem,
            roomInfo: info,
            eventSource: eventSource
          )
        }
      )
    }

    self.app.encoder = JSONEncoder()
    self.app.decoder = JSONDecoder()
    self.app.ws.addUpgrade()
    self.app.ws.add(middleware: HBLogRequestsMiddleware(.info))
    self.configure(
        router: app.router
      )
    let events = WebsocketApi.configure(builder: app.ws)
    self.listenForConnections(events: events)
    self.findDatabaseNodes()
    try self.app.start()
  }
}

extension FrontendNode {
  
  private func listenForConnections(events: AsyncStream<WebsocketApi.Event>) {
    self.wsConnectionListeningTask = Task {
      for await event in events {
        await self.handle(event: event)
      }
    }
  }
  
  private func handle(event: WebsocketApi.Event) async {
    switch event {
    case .close(let info):
      self.closeConnectionFor(userId: info.userId)
    case .connect(let info):
      do {
        let databaseNode = try await self.getDatabaseNode()
        let persistence = try await databaseNode.getPersistence()
        let room = try await self.findRoom(with: info)
        let userModel = try await persistence.getUser(id: info.userId)
        // userId key won't work with mulptiple devices
        // TODO: Create another key
        self.wsConnections[info.userId] = try await WebsocketConnection(
          actorSystem: self.actorSystem,
          ws: info.ws,
          databaseNodeId: databaseNode.id,
          persistence: persistence,
          room: room,
          userModel: userModel
        )
      } catch {
        try? await info.ws.close()
      }
    }
  }
  
  private func closeConnectionFor(userId: UUID) {
    let connection = self.wsConnections[userId]
    Task { await connection?.close() }
    self.wsConnections[userId] = .none
  }
  
  private func checkConnections(with databaseNode: DatabaseNode) {
    for (userId, connection) in self.wsConnections where connection.databaseNodeId == databaseNode.id {
      self.closeConnectionFor(userId: userId)
      Task {
        let info = try await connection.room.getRoomInfo()
        try await self.roomFactory.closeActor(for: info)
      }
    }
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
    return try await self.roomFactory
      .get(
        id: roomInfo,
        dependency: databaseNode.getEventSource()
      )
  }
}

extension FrontendNode: LifecycleWatch {
  
  func terminated(actor id: DistributedCluster.ActorID) {
    if let databaseNode = self.databaseNodes.first(where: { $0.id == id }) {
      self.httpConnections[id] = .none
      self.databaseNodes.remove(databaseNode)
      self.checkConnections(with: databaseNode)
      if self.databaseNodes.isEmpty {
        Task { try await self.spawnDatabaseNode() }
      }
    }
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
        
        self.httpConnections[databaseNode.id] = try? await HttpConnection(
          persistence: databaseNode.getPersistence()
        )
      }
    }
  }

  distributed private func getDatabaseNode() async throws -> DatabaseNode {
    guard let databaseNode = self.databaseNodes.randomElement() else {
      return try await spawnDatabaseNode()
    }
    return databaseNode
  }
  
  @discardableResult
  private func spawnDatabaseNode() async throws -> DatabaseNode {
    if let localDatabaseNode { return localDatabaseNode }
    let databaseNode = try await DatabaseNode(
      actorSystem: self.actorSystem
    )
    self.localDatabaseNode = databaseNode
    return databaseNode
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

  private func getConnection() throws -> HttpConnection {
    guard let worker = self.httpConnections.values.shuffled().first else {
      actorSystem.log.error("No workers to submit job to. Workers: \(self.httpConnections)")
      throw Error.noConnection
    }
    return worker
  }
}

extension FrontendNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {
    let feNode = await ClusterSystem("frontend") {
      $0.bindHost = host
      $0.bindPort = port
      $0.plugins.install(plugin: ClusterSingletonPlugin())
    }
    // We need references for ARC not to clean them up
    let frontend = try await Self(
      actorSystem: feNode
    )
    try await feNode.terminated
  }
}
