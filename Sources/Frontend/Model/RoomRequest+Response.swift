import Foundation
import Hummingbird

public struct CreateRoomRequest: Sendable, Equatable, ResponseCodable {
  public let name: String
  public let description: String?
}

public struct SearchRoomRequest: Sendable, Equatable, ResponseCodable {
  public let query: String
}

public struct RoomResponse: Sendable, Equatable, ResponseCodable {
  public let id: UUID
  public let name: String
  public let description: String?

  public init(id: UUID, name: String, description: String?) {
    self.id = id
    self.name = name
    self.description = description
  }
}
