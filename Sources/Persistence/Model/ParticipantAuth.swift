import Foundation

public struct ParticipantAuth: Sendable, Codable, Equatable {
  public let participant: ParticipantModel
  public let passwordHash: String

  public init(participant: ParticipantModel, passwordHash: String) {
    self.participant = participant
    self.passwordHash = passwordHash
  }
}
