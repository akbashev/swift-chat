import FoundationEssentials
import Hummingbird

public struct CreateRoomRequest: Sendable, Equatable, HBResponseCodable {
  public let id: String?
  public let name: String
}

public struct RoomResponse: Sendable, Equatable, HBResponseCodable {
  public let id: UUID
  public let name: String
  
  public init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }
}
