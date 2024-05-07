import Foundation
import Hummingbird

public struct CreateUserRequest: Sendable, Equatable, ResponseCodable {
  public let name: String
}

public struct UserResponse: Sendable, Equatable, ResponseCodable {
  public let id: UUID
  public let name: String
  
  public init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }
}
