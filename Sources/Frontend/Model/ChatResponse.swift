import Foundation

public struct ChatResponse: Sendable, Codable {
  
  public enum Message: Sendable, Codable, Equatable {
    case join
    case message(String, at: Date)
    case leave
    case disconnect
  }

  public let message: Message
  public let room: RoomResponse?
  public let user: UserResponse

  public init(
    user: UserResponse,
    room: RoomResponse? = nil,
    message: Message
  ) {
    self.user = user
    self.room = room
    self.message = message
  }
}
