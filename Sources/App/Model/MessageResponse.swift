import Foundation

public struct MessageResponse: Identifiable, Equatable, Codable {

  public var id: String {
    [self.user.id.uuidString, self.room?.id.uuidString, message.id]
      .compactMap { $0 }
      .joined(separator: "_ bn")
  }
  
  let user: UserResponse
  let room: RoomResponse?
  let message: Message
}
