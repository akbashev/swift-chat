import Distributed
import DistributedCluster

public distributed actor User {
  
  public typealias ActorSystem = ClusterSystem
  
  public enum Message: Sendable, Codable, Equatable {
    case join
    case message(String)
    case leave
    case disconnect
  }
  
  private var state: State
  private let reply: Reply
  
  // API
  distributed public func send(message: Message, to room: Room) async throws {
    switch message {
      case .join:
        try await self.join(room: room)
      case .message(let string):
        try await room.send(.message(string), from: self)
      case .leave:
        try await self.leave(room: room)
      case .disconnect:
        try await self.disconnect(room: room)
    }
  }
    
  // Room
  distributed func notify(_ message: User.Message, user: User, from room: Room) {
    Task {
      let userInfo = try await user.getUserInfo()
      try await self.reply.send(
        Output.message(
          .init(
            createdAt: .init(),
            roomId: room.getRoomInfo().id,
            userId: userInfo.id,
            message: message
          )
        )
      )
    }
  }
  
  distributed public func getUserInfo() -> UserInfo {
    self.state.info
  }
  
  public init(
    actorSystem: ClusterSystem,
    userInfo: UserInfo,
    reply: Reply
  ) async throws {
    self.actorSystem = actorSystem
    self.state = .init(
      info: userInfo
    )
    self.reply = reply
    await self.actorSystem.receptionist.checkIn(self, with: .users)
  }
  
  private func join(room: Room) async throws {
    try await room.send(.join, from: self)
    self.state.rooms.insert(room)
  }
  
  private func leave(room: Room) async throws {
    guard self.state.rooms.contains(room) else { throw User.Error.roomIsNotAvailable }
    try await room.send(.leave, from: self)
    self.state.rooms.remove(room)
  }
  
  private func disconnect(room: Room) async throws {
    guard self.state.rooms.contains(room) else { throw User.Error.roomIsNotAvailable }
    try await room.send(.disconnect, from: self)
  }
}

extension User {
  
  public struct Reply {
    public let send: @Sendable (Output) async throws -> ()
    
    public init(send: @escaping @Sendable (Output) async throws -> Void) {
      self.send = send
    }
  }
  
  public enum Error: Swift.Error {
    case roomIsNotAvailable
  }
  
  public enum Output: Codable, Sendable {
    case message(MessageInfo)
  }

  private struct State: Equatable {
    var rooms: Set<Room> = .init()
    let info: UserInfo
  }
}

extension DistributedReception.Key {
  public static var users: DistributedReception.Key<User> { "users" }
}
