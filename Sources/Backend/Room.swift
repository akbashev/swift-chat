import Distributed
import DistributedCluster
import EventSource
import Foundation
import VirtualActor
import EventSourcing

public distributed actor Room: EventSourced, VirtualActor {
  public typealias ActorSystem = ClusterSystem
  public typealias Command = Message
  
  public static var virtualFactoryKey: String = "rooms"
  
  @ActorID.Metadata(\.persistenceID)
  var persistenceId: PersistenceID
  
  @ActorID.Metadata(\.virtualID)
  var virtualId: VirtualID
  
  private var state: State
  private var users: Set<User> = .init()
  
  distributed func send(_ message: User.Message, from user: User) async throws {
    let userInfo = try await user.getUserInfo()
    let event: Event = switch message {
    case .join:
        .user(userInfo, .joined)
    case .message(let chatMessage, let date):
        .user(userInfo, .messageSent(chatMessage, at: date))
    case .leave:
        .user(userInfo, .left)
    case .disconnect:
        .user(userInfo, .disconnected)
    }
    do {
      /// We're saving state by saving an event
      /// Emit function also calls `handleEvent(_:)` internally, so will update state
      /// Otherwise—don't update the state! Order and fact of saving is important.
      try await self.emit(event: event)
    } catch {
      // Retry?
      self.actorSystem.log.error("Emitting failed, reason: \(error)")
    }
    // after saving event—update other states
    switch message {
    case .join:
      self.users.insert(user)
    case .leave,
        .disconnect:
      self.users.remove(user)
    default:
      break
    }
    await self.notifyOthersAbout(
      message: message,
      from: user
    )
  }
  
  distributed public func handleEvent(_ event: Event) {
    switch event {
    case .user(let user, let action):
      switch action {
      case .joined:
        self.state.users.insert(user)
      case .messageSent(let message, let date):
        self.state.messages[user, default: []].append(
          .init(
            roomId: self.state.info.id,
            userId: user.id,
            message: .message(message, at: date)
          )
        )
      case .left,
          .disconnected:
        self.state.users.remove(user)
      }
    }
  }

  distributed public func getRoomInfo() -> RoomInfo {
    self.state.info
  }
  
  distributed public func getMessages() -> [UserInfo: [MessageInfo]] {
    self.state.messages
  }
  
  public init(
    actorSystem: ClusterSystem,
    roomInfo: RoomInfo
  ) async {
    self.actorSystem = actorSystem
    self.state = .init(info: roomInfo, users: [], messages: [:])
    let roomId = roomInfo.id.rawValue.uuidString
    self.persistenceId = roomId
    self.virtualId = roomId
  }
  
  private func notifyOthersAbout(message: User.Message, from user: User) async {
    await withTaskGroup(of: Void.self) { group in
      for other in self.users where user.id != other.id {
        group.addTask {
          try? await other.notify(message, user: user, from: self)
        }
      }
    }
  }
}

extension Room {
  
  public enum Message: Sendable, Codable, Equatable {
    case fromUser(UserInfo, content: User.Message)
  }
  
  public enum Event: Sendable, Codable, Equatable {
    public enum Action: Sendable, Codable, Equatable {
      case joined
      case messageSent(String, at: Date)
      case left
      case disconnected
    }
    case user(UserInfo, Action)
  }
  
  public enum Error: Swift.Error {
    case userIsMissing
  }

  public struct State: Sendable, Codable, Equatable {
    let info: RoomInfo
    var users: Set<UserInfo> = .init()
    var messages: [UserInfo: [MessageInfo]] = [:]
    
    public init(
      info: RoomInfo,
      users: Set<UserInfo>,
      messages: [UserInfo: [MessageInfo]]
    ) {
      self.info = info
      self.users = users
      self.messages = messages
    }
  }
}
