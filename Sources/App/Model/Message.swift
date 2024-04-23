import Foundation

public enum Message: Identifiable, Sendable, Codable, Equatable {
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
