import HummingbirdFoundation
import HummingbirdWebSocket
import Distributed
import DistributedCluster
import Foundation

public protocol RestApi {
  func createUser(_ request: CreateUserRequest) async throws -> UserResponse
  func creteRoom(_ request: CreateRoomRequest) async throws -> RoomResponse
  func searchRoom(_ request: SearchRoomRequest) async throws -> [RoomResponse]
}

extension RestApi {
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
