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
  case join(Date)
  case message(String, at: Date)
  case disconnect(Date)

  public var id: String {
    switch self {
    case .join(let date): "join_\(date.description)"
    case .message(let message, let date): "message_\(message)_\(date.description)"
    case .disconnect(let date): "disconnect_\(date.description)"
    }
  }
}

extension MessagePresentation {
  init?(_ message: ChatClient.Message) throws {
    self.user = try .init(message.user)
    self.room = try .init(message.room)
    switch message.message {
    case .DisconnectMessage(let value):
      self.message = .disconnect(value.disconnectedAt)
    case .JoinMessage(let value):
      self.message = .join(value.joinedAt)
    case .TextMessage(let message):
      self.message = .message(message.content, at: message.timestamp)
    case .HeartbeatMessage:
      return nil
    }
  }
}
