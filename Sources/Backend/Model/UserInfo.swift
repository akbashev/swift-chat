import Foundation

public struct UserInfo: Sendable, Codable, Equatable {
  
  public struct ID: Sendable, Codable, Equatable, RawRepresentable {
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
