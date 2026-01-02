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
  init(_ output: Operations.Login.Output) throws {
    switch output {
    case .ok(let response):
      let payload = try response.body.json
      guard let id = UUID(uuidString: payload.id) else {
        throw ParseMappingError.participant
      }
      self.id = id
      self.name = payload.name
    case .unauthorized:
      throw AuthError.invalidCredentials
    case .undocumented(let statusCode, _):
      throw AuthError.unexpectedResponse(statusCode)
    }
  }

  init(_ output: Operations.Register.Output) throws {
    switch output {
    case .ok(let response):
      let payload = try response.body.json
      guard let id = UUID(uuidString: payload.id) else {
        throw ParseMappingError.participant
      }
      self.id = id
      self.name = payload.name
    case .conflict:
      throw AuthError.nameTaken
    case .undocumented(let statusCode, _):
      throw AuthError.unexpectedResponse(statusCode)
    }
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

enum AuthError: LocalizedError {
  case invalidCredentials
  case nameTaken
  case unexpectedResponse(Int)

  var errorDescription: String? {
    switch self {
    case .invalidCredentials:
      return "Invalid credentials."
    case .nameTaken:
      return "Name is already taken. Please choose another."
    case .unexpectedResponse(let statusCode):
      return "Unexpected response (\(statusCode))."
    }
  }
}
