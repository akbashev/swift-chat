import Foundation

public struct CreateParticipant: Sendable, Codable, Equatable {
  public let id: UUID
  public let createdAt: Date
  public let name: String
  public let passwordHash: String

  public init(
    id: UUID,
    createdAt: Date,
    name: String,
    passwordHash: String
  ) {
    self.id = id
    self.createdAt = createdAt
    self.name = name
    self.passwordHash = passwordHash
  }
}
