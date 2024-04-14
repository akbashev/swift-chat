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
    case environmentNotSet
  }
  
  private var wsConnections: [UUID: WebsocketConnection] = [:]
  private var wsConnectionListeningTask: Task<Void, Never>?
  let persistence: Persistence
  
  private let roomFactory: VirtualActorFactory<Room, RoomInfo>
  private lazy var app = HBApplication(
    configuration: .init(
      address: .hostname(
        self.actorSystem.cluster.node.host,
        port: 8080
      ),
      serverName: "frontend"
    )
  )
  
  init(
    actorSystem: ClusterSystem
  ) async throws {
    self.actorSystem = actorSystem
    let config = try Self.postgresConfig(
      host: actorSystem.cluster.node.endpoint.host
    )
    self.persistence = try await Persistence(
      type: .postgres(config)
    )
    self.roomFactory = try await actorSystem.singleton.host(name: "roomFactory") { actorSystem in
      await .init(
        actorSystem: actorSystem,
        spawn: { actorSystem, info in
          await Room(
            actorSystem: actorSystem,
            roomInfo: info
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
        let room = try await self.findRoom(with: info)
        let userModel = try await persistence.getUser(id: info.userId)
        // userId key won't work with mulptiple devices
        // TODO: Create another key
        self.wsConnections[info.userId] = try await WebsocketConnection(
          actorSystem: self.actorSystem,
          ws: info.ws,
          persistence: self.persistence,
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
  
  private func findRoom(
    with info: WebsocketApi.Event.Info
  ) async throws -> Room {
    let roomModel = try await self.persistence.getRoom(id: info.roomId)
    let roomInfo = RoomInfo(
      id: roomModel.id,
      name: roomModel.name,
      description: roomModel.description
    )
    return try await self.roomFactory
      .get(
        id: roomInfo
      )
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
      $0.plugins.install(plugin: ClusterSingletonPlugin())
      $0.plugins.install(
        plugin: ClusterJournalPlugin {
          MemoryEventStore(actorSystem: $0)
        }
      )
    }
    let frontend = try await FrontendNode(
      actorSystem: actorSystem
    )
    try await actorSystem.terminated
  }
}


extension FrontendNode {
  private static func postgresConfig(
    host: String
  ) throws -> PostgresConnection.Configuration {
    let env = HBEnvironment()
    guard let username = env.get("DB_USERNAME"),
          let password = env.get("DB_PASSWORD"),
          let database = env.get("DB_NAME") else {
      throw Self.Error.environmentNotSet
    }
    
    return PostgresConnection.Configuration(
      host: host,
      port: 5432,
      username: username,
      password: password,
      database: database,
      tls: .disable
    )
  }
}

/// Not quite _connection_ but will call for now.
extension FrontendNode: RestApi {
    
  distributed func createUser(_ request: Frontend.CreateUserRequest) async throws -> Frontend.UserResponse {
    let name = request.name
    let id = UUID()
    try await persistence.create(
      .user(
        .init(
          id: id,
          createdAt: .init(),
          name: request.name
        )
      )
    )
    return UserResponse(
      id: id,
      name: name
    )
  }
  
  distributed func creteRoom(_ request: Frontend.CreateRoomRequest) async throws -> Frontend.RoomResponse {
    let id = UUID()
    let name = request.name
    let description = request.description
    try await persistence.create(
      .room(
        .init(
          id: id,
          createdAt: .init(),
          name: request.name,
          description: request.description
        )
      )
    )
    return RoomResponse(
      id: id,
      name: name,
      description: description
    )
  }
  
  distributed func searchRoom(_ request: Frontend.SearchRoomRequest) async throws -> [Frontend.RoomResponse] {
    try await persistence
      .searchRoom(query: request.query)
      .map {
        RoomResponse(
          id: $0.id,
          name: $0.name,
          description: $0.description
        )
      }
  }
}
