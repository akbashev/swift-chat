import Foundation

public struct MessagePresentation: Identifiable, Equatable, Sendable {

  public var id: String {
    [self.user.id.uuidString, self.room.id.uuidString, message.id]
      .compactMap { $0 }
      .joined(separator: "_ bn")
  }

  let user: UserPresentation
  let room: RoomPresentation
  let message: Message
}

public enum Message: Identifiable, Equatable, Sendable {
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

extension MessagePresentation {
  init?(_ message: ChatClient.Message) throws {
    self.user = try .init(message.user)
    self.room = try .init(message.room)
    switch message.message {
    case .DisconnectMessage:
      self.message = .disconnect
    case .JoinMessage:
      self.message = .join
    case .LeaveMessage:
      self.message = .leave
    case .TextMessage(let message):
      self.message = .message(message.content, at: message.timestamp)
    case .HeartbeatMessage:
      return nil
    }
  }
}
