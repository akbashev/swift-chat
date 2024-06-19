import Hummingbird
import Foundation
import API
import Backend
import Persistence
import EventSource
import Distributed
import DistributedCluster
import PostgresNIO
import VirtualActor
import OpenAPIHummingbird
import OpenAPIRuntime

distributed actor FrontendNode {
  
  enum Error: Swift.Error {
    case noConnection
    case noDatabaseAvailable
    case environmentNotSet
    case unsupportedType
    case alreadyConnected
  }
  
  init(
    actorSystem: ClusterSystem
  ) async throws {
    self.actorSystem = actorSystem
    let env = Environment()
    let config = try Self.postgresConfig(
      host: actorSystem.cluster.node.endpoint.host,
      environment: env
    )
    let persistence = try await Persistence(
      type: .postgres(config)
    )
    let clientServerConnectionHandler = ClientServerConnectionHandler(
      actorSystem: actorSystem,
      persistence: persistence
    )
    let router = Router()
    let handler = RestApi(
      clientServerConnectionHandler: clientServerConnectionHandler,
      persistence: persistence
    )
    try handler.registerHandlers(on: router)
    var app = Application(
      router: router,
      configuration: .init(
        address: .hostname(
          self.actorSystem.cluster.node.host,
          port: 8080
        ),
        serverName: "frontend"
      )
    )
    app.addServices(clientServerConnectionHandler)
    try await app.runService()
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
struct RestApi: APIProtocol {
  
  let clientServerConnectionHandler: ClientServerConnectionHandler
  let persistence: Persistence
  
  func getMessages(_ input: Operations.getMessages.Input) async throws -> Operations.getMessages.Output {
    let eventStream = try await self.clientServerConnectionHandler.getStream(info: input)
    let chosenContentType = input.headers.accept.sortedByQuality().first ?? .init(contentType: .application_jsonl)
    let responseBody: Operations.getMessages.Output.Ok.Body = switch chosenContentType.contentType {
    case .application_jsonl:
        .application_jsonl(
          .init(eventStream.asEncodedJSONLines(), length: .unknown, iterationBehavior: .single)
        )
    case .other:
      throw FrontendNode.Error.unsupportedType
    }
    return .ok(.init(body: responseBody))
  }
    
  func searchRoom(_ input: API.Operations.searchRoom.Input) async throws -> API.Operations.searchRoom.Output {
    let rooms = try await persistence
      .searchRoom(query: input.query.query)
      .map {
        Components.Schemas.RoomResponse(
          id: $0.id.uuidString,
          name: $0.name,
          description: $0.description
        )
      }
    return .ok(.init(body: .json(rooms)))
  }
  
  func createUser(_ input: API.Operations.createUser.Input) async throws -> API.Operations.createUser.Output {
    guard
      let name = switch input.body {
      case .json(let payload): payload.name
      }
    else {
      throw FrontendNode.Error.noConnection
    }
    let id = UUID()
    try await persistence.create(
      .user(
        .init(
          id: id,
          createdAt: .init(),
          name: name
        )
      )
    )
    return .ok(
      .init(
        body: .json(
          .init(
            id: id.uuidString,
            name: name
          )
        )
      )
    )
  }
  
  func createRoom(_ input: Operations.createRoom.Input) async throws -> Operations.createRoom.Output {
    guard
      let name = switch input.body {
      case .json(let payload): payload.name
      }
    else {
      throw FrontendNode.Error.noConnection
    }
    let id = UUID()
    let description = switch input.body {
    case .json(let payload): payload.description
    }
    try await persistence.create(
      .room(
        .init(
          id: id,
          createdAt: .init(),
          name: name,
          description: description
        )
      )
    )
    return .ok(
      .init(
        body: .json(
          .init(
            id: id.uuidString,
            name: name,
            description: description
          )
        )
      )
    )
  }
}
