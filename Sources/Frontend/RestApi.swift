import Hummingbird
import HummingbirdCore
import HummingbirdRouter

public struct RestApi {
  public let createUser: (_ request: CreateUserRequest) async throws -> UserResponse
  public let creteRoom: (_ request: CreateRoomRequest) async throws -> RoomResponse
  public let searchRoom: (_ request: SearchRoomRequest) async throws -> [RoomResponse]
  
  public init(
    createUser: @escaping (_: CreateUserRequest) async throws -> UserResponse,
    creteRoom: @escaping (_: CreateRoomRequest) async throws -> RoomResponse,
    searchRoom: @escaping (_: SearchRoomRequest) async throws -> [RoomResponse]
  ) {
    self.createUser = createUser
    self.creteRoom = creteRoom
    self.searchRoom = searchRoom
  }
}

public extension RestApi {
  static func configure(
    router: Router<BasicRequestContext>,
    using api: RestApi
  ) {
    router.middlewares.add(LogRequestsMiddleware(.debug))
    router.get("hello") { _, _ in "Hello"}
    router.post("user") { req, context in
      guard let user = try? await req.decode(as: CreateUserRequest.self, context: context)
      else { throw HTTPError(.badRequest) }
      return try await api.createUser(user)
    }
    router.post("room") { req, context in
      guard let room = try? await req.decode(as: CreateRoomRequest.self, context: context)
      else { throw HTTPError(.badRequest) }
      return try await api.creteRoom(room)
    }
    router.get("room/search") { req, context in
      guard let query = req.uri
        .queryParameters
        .get("query", as: String.self) else { throw HTTPError(.badRequest) }
      return try await api.searchRoom(.init(query: query))
    }
  }
}


