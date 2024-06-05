import Foundation

public struct MessagePresentation: Identifiable, Equatable {
  
  public var id: String {
    [self.user.id.uuidString, self.room.id.uuidString, message.id]
      .compactMap { $0 }
      .joined(separator: "_ bn")
  }
  
  let user: UserPresentation
  let room: RoomPresentation
  let message: Message
}

public enum Message: Identifiable, Equatable {
  case join
  case message(String, at: Date)
  case leave
  case disconnect
  
  public var id: String {
    switch self {
    case .join: "join"
    case .message(let message, let date): "message_\(message)_\(date.description)"
    case .leave: "leave"
    case .disconnect: "disconnect"
    }
  }
}
