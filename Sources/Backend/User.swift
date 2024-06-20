import Distributed
import DistributedCluster
import Foundation

public distributed actor User {
  
  public typealias ActorSystem = ClusterSystem
  public typealias Reply = @Sendable ([Output]) async throws -> ()

  private var state: State
  private let reply: Reply
  
  distributed public var info: User.Info {
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
    
  /// Response, for performance reasone this function can already accept an array.
  distributed func handle(response: [Output]) async throws {
    try await self.reply(response)
  }
  
  public init(
    actorSystem: ClusterSystem,
    userInfo: User.Info,
    reply: @escaping Reply
  ) {
    self.actorSystem = actorSystem
    self.state = .init(
      info: userInfo
    )
    self.reply = reply
  }
  
  private func join(room: Room) async throws {
    let roomInfo = try await room.info
    guard !self.state.rooms.contains(roomInfo) else { throw User.Error.alreadyJoined }
    try await room.send(.join, from: self)
    self.state.rooms.insert(roomInfo)
  }
  
  private func leave(room: Room) async throws {
    let roomInfo = try await room.info
    guard self.state.rooms.contains(roomInfo) else { throw User.Error.roomIsNotAvailable }
    try await room.send(.leave, from: self)
    self.state.rooms.remove(roomInfo)
  }
  
  private func disconnect(room: Room) async throws {
    let roomInfo = try await room.info
    guard self.state.rooms.contains(roomInfo) else { throw User.Error.roomIsNotAvailable }
    try await room.send(.disconnect, from: self)
    self.state.rooms.remove(roomInfo)
  }
}

extension User {
  
  public struct Info: Sendable, Hashable, Codable, Equatable {
    
    public struct ID: Sendable, Hashable, Codable, Equatable, RawRepresentable {
      public let rawValue: UUID
      
      public init(rawValue: UUID) {
        self.rawValue = rawValue
      }
    }
    
    public let id: ID
    public let name: String
    
    public init(
      id: UUID,
      name: String
    ) {
      self.id = .init(rawValue: id)
      self.name = name
    }
  }
  
  public enum Message: Sendable, Codable, Equatable {
    case join
    case message(String, at: Date)
    case leave
    case disconnect
  }
  
  public enum Error: Swift.Error {
    case roomIsNotAvailable
    case alreadyJoined
  }
  
  public enum Output: Codable, Sendable {
    case message(MessageInfo)
  }

  private struct State: Equatable {
    var rooms: Set<Room.Info> = .init()
    let info: User.Info
  }
}
