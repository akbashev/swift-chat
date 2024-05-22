import Foundation

public struct RoomPresentation: Identifiable, Equatable {
  public let id: UUID
  public let name: String
  public let description: String?
  
  public init(id: UUID, name: String, description: String?) {
    self.id = id
    self.name = name
    self.description = description
  }
}
