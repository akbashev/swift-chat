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

  private var state: State
  private var users: Set<User> = .init()
  
  distributed public var info: Room.Info {
    get async throws { self.state.info }
  }
  
  distributed public var userMessages: [User.Info: [MessageInfo]] {
    get async throws { self.state.messages }
  }
  
  distributed func send(_ message: User.Message, from user: User) async throws {
    let userInfo = try await user.info
    let event: Event = switch message {
    case .join:
        .userDid(.joined, info: userInfo)
    case .message(let chatMessage, let date):
        .userDid(.sentMessage(chatMessage, at: date), info: userInfo)
    case .leave:
        .userDid(.left, info: userInfo)
    case .disconnect:
        .userDid(.disconnected, info: userInfo)
    }
    do {
      /// We're saving state by saving an event
      /// Emit function also calls `handleEvent(_:)` internally, so will update state
      /// Otherwise—don't update the state! Order and fact of saving is important.
      try await self.emit(event: event)
    } catch {
      // Retry?
      self.actorSystem.log.error("Emitting failed, reason: \(error)")
      throw error
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
    case .userDid(let action, let user):
      switch action {
      case .joined:
        self.state.users.insert(user)
      case .sentMessage(let message, let date):
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
  
  public init(
    actorSystem: ClusterSystem,
    roomInfo: Room.Info
  ) async {
    self.actorSystem = actorSystem
    self.state = .init(info: roomInfo, users: [], messages: [:])
    let roomId = roomInfo.id.rawValue.uuidString
    self.persistenceId = roomId
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
  
  public struct Info: Hashable, Sendable, Codable, Equatable {
    
    public struct ID: Sendable, Codable, Hashable, Equatable, RawRepresentable {
      public let rawValue: UUID
      
      public init(rawValue: UUID) {
        self.rawValue = rawValue
      }
    }

    public let id: ID
    public let name: String
    public let description: String?
    
    public init(
      id: UUID,
      name: String,
      description: String?
    ) {
      self.id = .init(rawValue: id)
      self.name = name
      self.description = description
    }
  }
  
  public enum Message: Sendable, Codable, Equatable {
    case fromUser(User.Info, content: User.Message)
  }
  
  public enum Event: Sendable, Codable, Equatable {
    public enum Action: Sendable, Codable, Equatable {
      case joined
      case sentMessage(String, at: Date)
      case left
      case disconnected
    }
    case userDid(Action, info: User.Info)
  }
  
  public enum Error: Swift.Error {
    case userIsMissing
  }

  public struct State: Sendable, Codable, Equatable {
    let info: Room.Info
    var users: Set<User.Info> = .init()
    var messages: [User.Info: [MessageInfo]] = [:]
    
    public init(
      info: Room.Info,
      users: Set<User.Info>,
      messages: [User.Info: [MessageInfo]]
    ) {
      self.info = info
      self.users = users
      self.messages = messages
    }
  }
}
