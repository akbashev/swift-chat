import FoundationEssentials
import HummingbirdWSCore
import HummingbirdWebSocket
import NIOWebSocket
import NIOCore

public enum ChatMessage: Codable {
  public enum Message: Codable {
    case text(String)
    case message(ChatResponse.Message)
    case messages([ChatResponse.Message])
  }
  
  case message(userId: UUID, roomId: UUID, message: Message)
  case close(userId: UUID, roomId: UUID)
  
  public var userId: UUID {
    switch self {
    case .message(let userId, _, _),
        .close(let userId, _):
      userId
    }
  }
  
  public var roomId: UUID {
    switch self {
    case .message(_, let roomId, _),
        .close(_, let roomId):
      roomId
    }
  }
}
