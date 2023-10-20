import FoundationEssentials

public struct RoomInfo: Sendable, Codable, Equatable {
  
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
