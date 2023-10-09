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
  let handle: @Sendable (ChatConnection) -> ()
  
  public init(
    createUser: @Sendable @escaping (CreateUserRequest) async throws -> UserResponse,
    creteRoom: @Sendable @escaping (CreateRoomRequest) async throws -> RoomResponse,
    searchRoom: @Sendable @escaping (SearchRoomRequest) async throws -> [RoomResponse],
    handle: @Sendable @escaping (ChatConnection) -> ()
  ) {
    self.createUser = createUser
    self.creteRoom = creteRoom
    self.searchRoom = searchRoom
    self.handle = handle
  }
}
