import Foundation
import Hummingbird

public struct CreateRoomRequest: Sendable, Equatable, HBResponseCodable {
  public let name: String
  public let description: String?
}

public struct SearchRoomRequest: Sendable, Equatable, HBResponseCodable {
  public let query: String
}

public struct RoomResponse: Sendable, Equatable, HBResponseCodable {
  public let id: UUID
  public let name: String
  public let description: String?

  public init(id: UUID, name: String, description: String?) {
    self.id = id
    self.name = name
    self.description = description
  }
}
