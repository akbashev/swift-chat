import Foundation

public struct RoomPresentation: Identifiable, Equatable, Hashable, Sendable {
  public let id: UUID
  public let name: String
  public let description: String?
  
  public init(id: UUID, name: String, description: String?) {
    self.id = id
    self.name = name
    self.description = description
  }
}

import API

extension RoomPresentation {
  init(_ output: Operations.createRoom.Output) throws {
    let payload = try output.ok.body.json
    try self.init(payload)
  }
}

extension RoomPresentation {
  init(_ response: Components.Schemas.RoomResponse) throws {
    guard
      let id = UUID(uuidString: response.id)
    else {
      throw ParseMappingError.room
    }
    self.id = id
    self.name = response.name
    self.description = response.description
  }
}
