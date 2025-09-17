import Foundation

public struct MessageEnvelope: Sendable, Codable, Equatable {

  public let room: Room.Info
  public let user: User.Info
  public let message: Room.Message

  public init(
    room: Room.Info,
    user: User.Info,
    message: Room.Message
  ) {
    self.room = room
    self.user = user
    self.message = message
  }
}
