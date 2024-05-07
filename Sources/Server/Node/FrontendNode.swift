import HummingbirdWSCore
import HummingbirdWebSocket
import Hummingbird
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
  
  let persistence: Persistence
  let connectionManager: WebsocketConnection
  lazy var router = Router()
  lazy var wsRouter = Router(context: BasicWebSocketRequestContext.self)
  lazy var app = Application(
    router: router,
    server: .http1WebSocketUpgrade(
      webSocketRouter: wsRouter,
      configuration: .init(extensions: [])
    ),
    configuration: .init(
      address: .hostname(
        self.actorSystem.cluster.node.host,
        port: 8080
      ),
      serverName: "frontend"
    )
  )
  lazy var api: RestApi = RestApi(
    createUser: { [weak self] request in
      guard let self else { throw Error.noConnection }
      return try await self.createUser(request)
    },
    creteRoom: { [weak self] request in
      guard let self else { throw Error.noConnection }
      return try await self.creteRoom(request)
    },
    searchRoom: { [weak self] request in
      guard let self else { throw Error.noConnection }
      return try await self.searchRoom(request)
    }
  )
  
  init(
    actorSystem: ClusterSystem
  ) async throws {
    self.actorSystem = actorSystem
    let env = Environment()
    let config = try Self.postgresConfig(
      host: actorSystem.cluster.node.endpoint.host,
      environment: env
    )
    self.persistence = try await Persistence(
      type: .postgres(config)
    )
    self.connectionManager = WebsocketConnection(
      actorSystem: actorSystem,
      persistence: self.persistence
    )
    RestApi.configure(
      router: self.router,
      using: self.api
    )
    WebsocketApi.configure(
      wsRouter: self.wsRouter,
      connectionManager: self.connectionManager
    )
    self.app.addServices(self.connectionManager)
    try await self.app.runService()
  }
}

extension FrontendNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {
    let frontendNode = await ClusterSystem("frontend") {
      $0.bindHost = host
      $0.bindPort = port
      $0.installPlugins()
    }
    // We need references for ARC not to clean them up
    let frontend = try await FrontendNode(
      actorSystem: frontendNode
    )
    try await frontendNode.terminated
  }
}


extension FrontendNode {
  private static func postgresConfig(
    host: String,
    environment: Environment
  ) throws -> PostgresConnection.Configuration {
    guard let username = environment.get("DB_USERNAME"),
          let password = environment.get("DB_PASSWORD"),
          let database = environment.get("DB_NAME") else {
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
extension FrontendNode {
  
  distributed func createUser(
    _ request: Frontend.CreateUserRequest
  ) async throws -> Frontend.UserResponse {
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
  
  distributed func creteRoom(
    _ request: Frontend.CreateRoomRequest
  ) async throws -> Frontend.RoomResponse {
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
  
  distributed func searchRoom(
    _ request: Frontend.SearchRoomRequest
  ) async throws -> [Frontend.RoomResponse] {
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
