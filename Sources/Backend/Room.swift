import Distributed
import DistributedCluster
import EventSource
import Foundation

public distributed actor Room: EventSourced {

  public typealias ActorSystem = ClusterSystem
  public typealias Command = Message
  
  public enum Message: Sendable, Codable, Equatable {
    case user(User, User.Message)
  }
  
  public enum Event: Sendable, Codable, Equatable {
    public enum Action: Sendable, Codable, Equatable {
      case joined
      case messageSent(ChatMessage)
      case left
      case disconnected
    }
    case user(UserInfo, Action)
  }
  
  public var state: State
  public var users: Set<User> = .init()
  public var persistenceId: PersistenceId {
    "room_\(self.state.info.id)"
  }
  
  distributed func message(_ message: User.Message, from user: User) async throws -> Event {
    let event = try await self.handle(command: .user(user, message))
    try self.handle(
      event: event
    )
    self.notifyOthersAbout(
      message: message,
      from: user
    )
  }

  distributed public func handle(command: Command) async throws -> Event {
    switch command {
    case .user(let user, let command):
      let userInfo = try await user.getUserInfo()
      switch command {
      case .join:
        users.insert(user)
        return .user(userInfo, .joined)
      case .message(let message):
        return .user(userInfo, .messageSent(message))
      case .leave:
        users.remove(user)
        return .user(userInfo, .left)
      case .disconnect:
        users.remove(user)
        return .user(userInfo, .disconnected)
      }
    }
  }
  
  public func handle(event: Event) throws {
    switch event {
    case .user(let user, let action):
      switch action {
      case .joined:
        self.state.users.insert(user)
      case .messageSent(let message):
        self.state.messages[user, default: []].append(message)
      case .left,
          .disconnected:
        self.state.users.remove(user)
      }
    }
    Task { await self.persist(event) }
  }
  
  distributed public func getRoomInfo() -> RoomInfo {
    self.state.info
  }
  
  distributed public func getMessages() -> [UserInfo: [ChatMessage]] {
    self.state.messages
  }
  
  public init(
    actorSystem: ClusterSystem,
    roomInfo: RoomInfo
  ) async throws {
    self.actorSystem = actorSystem
    let id = roomInfo.id.rawValue.uuidString.lowercased()
    self.state = .init(info: roomInfo, users: [], messages: [:])
//    self.state = try await eventSource
//      .get(
//        query: """
//        SELECT command FROM events WHERE event->'roomId'->>'rawValue' ILIKE '\(id)';
//        """
//      )
    await actorSystem
      .receptionist
      .checkIn(self, with: .rooms)
  }
  
  // non-structured
  private func notifyOthersAbout(message: User.Message, from user: User) {
    Task {
      await withThrowingTaskGroup(of: Void.self) { group in
        for other in self.users where user != other {
          group.addTask {
            try await other.notify(message, user: user, from: self)
          }
        }
      }
    }
  }
}

extension Room {
  
  public enum Error: Swift.Error {
    case userIsMissing
  }

  public struct State: Sendable, Codable, Equatable {
    let info: RoomInfo
    var users: Set<UserInfo> = .init()
    var messages: [UserInfo: [ChatMessage]] = [:]
    
    public init(
      info: RoomInfo,
      users: Set<UserInfo>,
      messages: [UserInfo: [ChatMessage]]
    ) {
      self.info = info
      self.users = users
      self.messages = messages
    }
  }
}

extension DistributedReception.Key {
  public static var rooms: DistributedReception.Key<Room> { "rooms" }
}
