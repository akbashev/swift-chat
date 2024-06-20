import Foundation

public struct UserPresentation: Identifiable, Codable, Equatable, Hashable, Sendable {
  public let id: UUID
  public let name: String
  
  public init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }
}
