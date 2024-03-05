import Foundation

public struct RoomModel: Sendable, Codable, Equatable {
  public let id: UUID
  public let createdAt: Date
  public let name: String
  public let description: String?
  
  public init(
    id: UUID,
    createdAt: Date,
    name: String,
    description: String?
  ) {
    self.id = id
    self.createdAt = createdAt
    self.name = name
    self.description = description
  }
}
