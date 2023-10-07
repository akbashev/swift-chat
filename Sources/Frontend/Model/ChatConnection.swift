import FoundationEssentials
import HummingbirdWebSocket

public struct ChatConnection: Sendable {
  public let userId: UUID
  public let roomId: UUID
  // TODO: Hide HBWebSocket under new abstraction
  public let ws: HBWebSocket
}
