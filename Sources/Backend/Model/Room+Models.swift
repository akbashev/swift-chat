import Foundation

extension Room {

  public enum Message: Sendable, Codable, Equatable {
    case join(Date)
    case message(String, at: Date)
    case disconnect(Date)
  }

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

  public enum Event: Sendable, Codable, Equatable {
    public enum Action: Sendable, Codable, Equatable {
      case joined(Date)
      case sentMessage(String, at: Date)
      case disconnected(Date)
    }
    case userDid(Action, info: User.Info)
  }

  public enum Error: Swift.Error, Codable, Sendable {
    case userIsMissing
    case userAlreadyJoined
  }

  struct State {
    let info: Room.Info
    var messages: [MessageEnvelope] = []
    var onlineUsers: Set<User> = .init()

    public init(
      info: Room.Info
    ) {
      self.info = info
    }
  }
}
