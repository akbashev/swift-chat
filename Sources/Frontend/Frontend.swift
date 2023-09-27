import HummingbirdFoundation
import HummingbirdWebSocket
import Distributed
import DistributedCluster

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
  
  let createUser: @Sendable (CreateUserRequest) async throws -> UserResponse
  let creteRoom: @Sendable (CreateRoomRequest) async throws -> RoomResponse
  let searchRoom: @Sendable (SearchRoomRequest) async throws -> [RoomResponse]
  let chat: @Sendable (AsyncStream<ChatConnection>) -> ()
  
  public init(
    createUser: @Sendable @escaping (CreateUserRequest) async throws -> UserResponse,
    creteRoom: @Sendable @escaping (CreateRoomRequest) async throws -> RoomResponse,
    searchRoom: @Sendable @escaping (SearchRoomRequest) async throws -> [RoomResponse],
    chat: @Sendable @escaping (AsyncStream<ChatConnection>) -> ()
  ) {
    self.createUser = createUser
    self.creteRoom = creteRoom
    self.searchRoom = searchRoom
    self.chat = chat
  }
}
