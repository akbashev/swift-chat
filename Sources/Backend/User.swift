import Distributed
import DistributedCluster
import Foundation

public distributed actor User {
  
  public typealias ActorSystem = ClusterSystem
  public typealias Reply = @Sendable (Output) async throws -> ()

  private var state: State
  private let reply: Reply
  
  distributed public var info: UserInfo {
    get async throws { self.state.info }
  }
  
  // API
  distributed public func send(message: Message, to room: Room) async throws {
    switch message {
      case .join:
        try await self.join(room: room)
      case .message(let string, let date):
        try await room.send(.message(string, at: date), from: self)
      case .leave:
        try await self.leave(room: room)
      case .disconnect:
        try await self.disconnect(room: room)
    }
  }
    
  // Room
  distributed func notify(_ message: User.Message, user: User, from room: Room) async throws {
    let userInfo = try await user.info
    try await self.reply(
      Output.message(
        .init(
          roomId: room.info.id,
          userId: userInfo.id,
          message: message
        ),
        from: userInfo
      )
    )
  }
  
  public init(
    actorSystem: ClusterSystem,
    userInfo: UserInfo,
    reply: @escaping Reply
  ) {
    self.actorSystem = actorSystem
    self.state = .init(
      info: userInfo
    )
    self.reply = reply
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
  
  public enum Message: Sendable, Codable, Equatable {
    case join
    case message(String, at: Date)
    case leave
    case disconnect
  }
  
  public enum Error: Swift.Error {
    case roomIsNotAvailable
  }
  
  public enum Output: Codable, Sendable {
    case message(MessageInfo, from: UserInfo)
  }

  private struct State: Equatable {
    var rooms: Set<Room> = .init()
    let info: UserInfo
  }
}
