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

public struct RoomResponse: Sendable, Codable, Equatable {
  public let id: UUID
  public let name: String
  public let description: String?
  
  public init(id: UUID, name: String, description: String?) {
    self.id = id
    self.name = name
    self.description = description
  }
}

public struct UserResponse: Sendable, Codable, Equatable {
  public let id: UUID
  public let name: String
  
  public init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }
}
