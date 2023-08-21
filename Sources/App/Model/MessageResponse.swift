import Foundation

public struct MessageResponse: Identifiable, Equatable, Codable {

  public var id: Date { self.createdAt }
  
  let createdAt: Date
  let user: UserResponse
  let room: RoomResponse?
  let message: Message
}
