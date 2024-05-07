import Foundation

public struct MessageInfo: Sendable, Codable, Equatable {
  
  public let roomInfo: Room.Info
  public let userInfo: User.Info
  public let message: User.Message
  
  public init(
    roomInfo: Room.Info,
    userInfo: User.Info,
    message: User.Message
  ) {
    self.roomInfo = roomInfo
    self.userInfo = userInfo
    self.message = message
  }
}
