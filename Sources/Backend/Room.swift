import Distributed
import DistributedCluster
import EventSource
import Foundation
import VirtualActor
import EventSourcing

public distributed actor Room: EventSourced, VirtualActor {
  
  public typealias ActorSystem = ClusterSystem
  
  @ActorID.Metadata(\.persistenceID)
  var persistenceId: PersistenceID

  private var state: State
  
  distributed public var info: Room.Info {
    get async throws { self.state.info }
  }
  
  distributed func send(_ message: User.Message, from user: User) async throws {
    let userInfo = try await user.info
    let action = Event.Action(message)
    let event = Event.userDid(action, info: userInfo)
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
      // Fetch all current room messages and send to user
      await self.sendCurrentMessagesTo(user: user)
      self.state.users.insert(user)
    case .leave,
        .disconnect:
      self.state.users.remove(user)
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
    case .userDid(let action, let userInfo):
      self.state.messages.append(
        .init(
          roomInfo: self.state.info,
          userInfo: userInfo,
          message: .init(action)
        )
      )
    }
  }
  
  public init(
    actorSystem: ClusterSystem,
    roomInfo: Room.Info
  ) async {
    self.actorSystem = actorSystem
    self.state = .init(info: roomInfo)
    let roomId = roomInfo.id.rawValue.uuidString
    self.persistenceId = roomId
  }
  
  private func sendCurrentMessagesTo(user: User) async {
    try? await user.handle(
      response: self.state
        .messages
        .map { .message($0) }
    )
  }
  
  private func notifyOthersAbout(message: User.Message, from user: User) async {
    await withTaskGroup(of: Void.self) { group in
      for user in self.state.users {
        group.addTask {
          try? await user.handle(
            response: [
              .message(
                .init(
                  roomInfo: self.state.info,
                  userInfo: user.info,
                  message: message
                )
              ),
            ]
          )
        }
      }
    }
  }
}

extension Room {
  
  public struct Info: Hashable, Sendable, Codable, Equatable, VirtualActorDependency {
    
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
    var users: Set<User> = .init()
    var messages: [MessageInfo] = []
    
    public init(
      info: Room.Info
    ) {
      self.info = info
    }
  }
}

extension User.Message {
  init(_ action: Room.Event.Action) {
    self = switch action {
    case .sentMessage(let message, let date):
        .message(message, at: date)
    case .left:
        .leave
    case .disconnected:
        .disconnect
    case .joined:
        .join
    }
  }
}

extension Room.Event.Action {
  init(_ message: User.Message) {
    self = switch message {
    case let .message(message, date):
        .sentMessage(message, at: date)
    case .leave:
        .left
    case .disconnect:
        .disconnected
    case .join:
        .joined
    }
  }
}
