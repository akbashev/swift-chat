import FoundationEssentials

public struct MessageInfo: Sendable, Codable, Equatable {
  public struct ID: Sendable, Codable, Equatable, RawRepresentable {
    public let rawValue: UUID
    
    public init(rawValue: UUID) {
      self.rawValue = rawValue
    }
  }
  
  public let id: ID
  public let room: RoomInfo
  public let user: UserInfo
  public let message: Message
  
  public init(
    id: UUID = UUID(),
    room: RoomInfo,
    user: UserInfo,
    message: Message
  ) {
    self.id = .init(rawValue: id)
    self.room = room
    self.user = user
    self.message = message
  }
}
