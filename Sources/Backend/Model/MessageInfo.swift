import Foundation

public struct MessageInfo: Sendable, Codable, Equatable {
  
  public let roomId: Room.Info.ID
  public let userId: User.Info.ID
  public let message: User.Message
  
  public init(
    roomId: Room.Info.ID,
    userId: User.Info.ID,
    message: User.Message
  ) {
    self.roomId = roomId
    self.userId = userId
    self.message = message
  }
}
