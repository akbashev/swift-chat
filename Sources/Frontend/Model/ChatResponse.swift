import Foundation

public struct ChatResponse: Sendable, Codable {
  
  public enum Message: Sendable, Codable, Equatable {
    case join
    case message(String)
    case leave
    case disconnect
  }

  public let createdAt: Date
  public let user: UserResponse
  public let message: Message
  public let room: RoomResponse?

  public init(
    createdAt: Date,
    user: UserResponse,
    room: RoomResponse? = nil,
    message: Message
  ) {
    self.createdAt = createdAt
    self.user = user
    self.room = room
    self.message = message
  }
}
