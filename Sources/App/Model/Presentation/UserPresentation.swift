import Foundation

public struct UserPresentation: Identifiable, Codable, Equatable, Hashable, Sendable {
  public let id: UUID
  public let name: String
  
  public init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }
}

import API

extension UserPresentation {
  init(_ output: Operations.createUser.Output) throws {
    let payload = try output.ok.body.json
    guard let id = UUID(uuidString: payload.id) else {
      throw ParseMappingError.user
    }
    self.id = id
    self.name = payload.name
  }
}

extension UserPresentation {
  init(_ response: Components.Schemas.UserResponse) throws {
    guard let id = UUID(uuidString: response.id) else {
      throw ParseMappingError.user
    }
    self.id = id
    self.name = response.name
  }
}

