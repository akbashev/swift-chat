import HummingbirdFoundation
import HummingbirdWebSocket
import Distributed
import DistributedCluster
import FoundationEssentials

public distributed actor Frontend {
  
  public typealias ActorSystem = ClusterSystem

  private let websocketClient: WebsocketClient
  private let httpClient: HttpClient
  
  public init(
    actorSystem: ClusterSystem,
    api: Api
  ) async throws {
    self.actorSystem = actorSystem
    let app = HBApplication(
      configuration: .init(
        address: .hostname(
          actorSystem.cluster.node.host,
          port: 8080
        ),
        serverName: "Frontend"
      )
    )

    app.encoder = JSONEncoder()
    app.decoder = JSONDecoder()
    
    self.websocketClient = WebsocketClient(ws: app.ws)
    self.httpClient = HttpClient(router: app.router)
    
    self.websocketClient.configure(api: api)
    self.httpClient.configure(api: api)
    
    try app.start()
  }
}

/// Protocol Witness Pointfree.co's style
/// https://www.pointfree.co/collections/protocol-witnesses/alternatives-to-protocols
public struct Api: Sendable {
  
  public struct ChatConnection {
    public let userId: UUID
    public let roomId: UUID
    // TODO: Hide HBWebSocket under new abstraction
    public let ws: HBWebSocket
  }
  
  public struct CreateUserRequest: Sendable, Equatable, HBResponseCodable {
    public let id: String?
    public let name: String
  }
  
  public struct CreateUserResponse: Sendable, Equatable, HBResponseCodable {
    public let id: UUID
    public let name: String
    
    public init(id: UUID, name: String) {
      self.id = id
      self.name = name
    }
  }
  
  public struct CreateRoomRequest: Sendable, Equatable, HBResponseCodable {
    public let id: String?
    public let name: String
  }
  
  public struct CreateRoomResponse: Sendable, Equatable, HBResponseCodable {
    public let id: UUID
    public let name: String
    
    public init(id: UUID, name: String) {
      self.id = id
      self.name = name
    }
  }
  
  let createUser: @Sendable (CreateUserRequest) async throws -> (CreateUserResponse)
  let creteRoom: @Sendable (CreateRoomRequest) async throws -> (CreateRoomResponse)
  let chat: @Sendable (AsyncStream<ChatConnection>) -> ()
  
  public init(
    createUser: @Sendable @escaping (CreateUserRequest) async throws -> (CreateUserResponse),
    creteRoom: @Sendable @escaping (CreateRoomRequest) async throws -> (CreateRoomResponse),
    chat: @Sendable @escaping (AsyncStream<ChatConnection>) -> ()
  ) {
    self.createUser = createUser
    self.creteRoom = creteRoom
    self.chat = chat
  }
}
