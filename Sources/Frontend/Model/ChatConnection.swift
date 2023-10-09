import FoundationEssentials
import HummingbirdWSCore
import HummingbirdWebSocket
import NIOWebSocket

public struct ChatConnection {
  
  public struct WebSocketConnection {
    public let close: (WebSocketErrorCode) async throws -> ()
    public let onClose: (@escaping HBWebSocket.CloseCallback) -> ()
    public let write: (WebSocketData) async throws -> ()
    public let messages: () -> AsyncStream<WebSocketData>
  }

  public let userId: UUID
  public let roomId: UUID
  public let ws: WebSocketConnection
}
