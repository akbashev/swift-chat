import Foundation

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
  
  
  public enum Error: Swift.Error {
    case roomIsNotAvailable
    case alreadyJoined
  }
  
  public enum Output: Codable, Sendable {
    case message(MessageEnvelope)
  }

  struct State: Equatable {
    let info: User.Info
  }
}
