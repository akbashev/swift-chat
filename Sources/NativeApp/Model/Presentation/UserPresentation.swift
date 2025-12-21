import Foundation
import Models

public struct ParticipantPresentation: Identifiable, Codable, Equatable, Hashable, Sendable {
  public let id: UUID
  public let name: String

  public init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }
}

extension ParticipantPresentation {
  init(_ output: Operations.Register.Output) throws {
    let payload = try output.ok.body.json
    guard let id = UUID(uuidString: payload.id) else {
      throw ParseMappingError.participant
    }
    self.id = id
    self.name = payload.name
  }
}

extension ParticipantPresentation {
  init(_ response: ParticipantResponse) throws {
    guard let id = UUID(uuidString: response.id) else {
      throw ParseMappingError.participant
    }
    self.id = id
    self.name = response.name
  }
}
