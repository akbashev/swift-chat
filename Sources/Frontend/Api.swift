import HummingbirdFoundation
import HummingbirdWebSocket
import Distributed
import DistributedCluster
import FoundationEssentials

/// Protocol Witness Pointfree.co's style
/// https://www.pointfree.co/collections/protocol-witnesses/alternatives-to-protocols
public struct Api: Sendable {
  
  public enum Error: Swift.Error {
    case noConnection
  }

  let createUser: @Sendable (CreateUserRequest) async throws -> UserResponse
  let creteRoom: @Sendable (CreateRoomRequest) async throws -> RoomResponse
  let searchRoom: @Sendable (SearchRoomRequest) async throws -> [RoomResponse]
  
  public init(
    createUser: @Sendable @escaping (CreateUserRequest) async throws -> UserResponse,
    creteRoom: @Sendable @escaping (CreateRoomRequest) async throws -> RoomResponse,
    searchRoom: @Sendable @escaping (SearchRoomRequest) async throws -> [RoomResponse]
  ) {
    self.createUser = createUser
    self.creteRoom = creteRoom
    self.searchRoom = searchRoom
  }
}

extension Api {
  public func configure(
    router: HBRouterBuilder
  ) {
    router.get("hello") { _ in
      return "Hello"
    }
    router.post("user") { req in
      guard let user = try? req.decode(as: CreateUserRequest.self)
      else { throw HBHTTPError(.badRequest) }
      return try await self.createUser(user)
    }
    router.post("room") { req in
      guard let room = try? req.decode(as: CreateRoomRequest.self)
      else { throw HBHTTPError(.badRequest) }
      return try await self.creteRoom(room)
    }
    router.get("room/search") { req in
      guard let query = req.uri
        .queryParameters
        .get("query", as: String.self) else { throw HBHTTPError(.badRequest) }
      return try await self.searchRoom(.init(query: query))
    }
  }
}
