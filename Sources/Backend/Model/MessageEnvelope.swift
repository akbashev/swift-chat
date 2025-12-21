import Foundation

public struct MessageEnvelope: Sendable, Codable, Equatable {

  public let room: Room.Info
  public let participant: Participant.Info
  public let message: Room.Message

  public init(
    room: Room.Info,
    participant: Participant.Info,
    message: Room.Message
  ) {
    self.room = room
    self.participant = participant
    self.message = message
  }
}
