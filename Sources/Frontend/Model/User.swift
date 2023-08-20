import FoundationEssentials
import Hummingbird

public struct CreateUserRequest: Sendable, Equatable, HBResponseCodable {
  public let id: String?
  public let name: String
}

public struct UserResponse: Sendable, Equatable, HBResponseCodable {
  public let id: UUID
  public let name: String
  
  public init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }
}
