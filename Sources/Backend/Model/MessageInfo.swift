import Foundation

public struct MessageInfo: Sendable, Codable, Equatable {
  public let createdAt: Date
  public let roomId: RoomInfo.ID
  public let userId: UserInfo.ID
  public let message: Message
  
  public init(
    createdAt: Date,
    roomId: RoomInfo.ID,
    userId: UserInfo.ID,
    message: Message
  ) {
    self.createdAt = createdAt
    self.roomId = roomId
    self.userId = userId
    self.message = message
  }
}
