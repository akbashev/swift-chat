import Foundation
import VirtualActor

extension Room {
  
  public enum Message: Sendable, Codable, Equatable {
    case join
    case message(String, at: Date)
    case leave
    case disconnect
  }
  
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

  struct State: Sendable, Codable, Equatable {
    let info: Room.Info
    var messages: [MessageEnvelope] = []
    
    public init(
      info: Room.Info
    ) {
      self.info = info
    }
  }
}
