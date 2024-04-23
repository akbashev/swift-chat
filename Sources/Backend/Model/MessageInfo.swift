import Foundation

public struct MessageInfo: Sendable, Codable, Equatable {
  
  public let roomId: RoomInfo.ID
  public let userId: UserInfo.ID
  public let message: User.Message
  
  public init(
    roomId: RoomInfo.ID,
    userId: UserInfo.ID,
    message: User.Message
  ) {
    self.roomId = roomId
    self.userId = userId
    self.message = message
  }
}
