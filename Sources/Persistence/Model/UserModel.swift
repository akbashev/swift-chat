import Foundation

public struct UserModel: Sendable, Codable, Equatable {
  public let id: UUID
  public let createdAt: Date
  public let name: String

  public init(
    id: UUID,
    createdAt: Date,
    name: String
  ) {
    self.id = id
    self.createdAt = createdAt
    self.name = name
  }
}
