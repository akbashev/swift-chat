import Foundation
import Models
import Persistence

/// Implementation of OpenAPI `APIProtocol` for backend
public struct Api: APIProtocol {

  enum Error: Swift.Error {
    case noConnection
    case noDatabaseAvailable
    case unsupportedType
    case alreadyConnected
  }

  let clientServerConnectionHandler: ClientServerConnectionHandler
  let persistence: Persistence

  public init(
    clientServerConnectionHandler: ClientServerConnectionHandler,
    persistence: Persistence
  ) {
    self.clientServerConnectionHandler = clientServerConnectionHandler
    self.persistence = persistence
  }

  public func getMessages(
    _ input: Operations.GetMessages.Input
  ) async throws
    -> Operations.GetMessages.Output
  {
    let eventStream = try await self.clientServerConnectionHandler.getStream(info: input)
    let chosenContentType =
      input.headers.accept.sortedByQuality().first ?? .init(contentType: .applicationJsonl)
    let responseBody: Operations.GetMessages.Output.Ok.Body =
      switch chosenContentType.contentType {
      case .applicationJsonl:
        .applicationJsonl(
          .init(eventStream.asEncodedJSONLines(), length: .unknown, iterationBehavior: .single)
        )
      case .other:
        throw Api.Error.unsupportedType
      }
    return .ok(.init(body: responseBody))
  }

  public func searchRoom(
    _ input: Operations.SearchRoom.Input
  ) async throws
    -> Operations.SearchRoom.Output
  {
    let rooms =
      try await persistence
      .searchRoom(query: input.query.query)
      .map {
        RoomResponse(
          id: $0.id.uuidString,
          name: $0.name,
          description: $0.description
        )
      }
    return .ok(.init(body: .json(rooms)))
  }

  public func createUser(
    _ input: Operations.CreateUser.Input
  ) async throws -> Operations.CreateUser.Output {
    guard
      let name =
        switch input.body {
        case .json(let payload): payload.name
        }
    else {
      throw Api.Error.noConnection
    }
    let id = UUID()
    try await persistence.create(
      .user(
        .init(
          id: id,
          createdAt: .init(),
          name: name
        )
      )
    )
    return .ok(
      .init(
        body: .json(
          .init(
            id: id.uuidString,
            name: name
          )
        )
      )
    )
  }

  public func createRoom(_ input: Operations.CreateRoom.Input) async throws -> Operations.CreateRoom.Output {
    guard
      let name =
        switch input.body {
        case .json(let payload): payload.name
        }
    else {
      throw Api.Error.noConnection
    }
    let id = UUID()
    let description =
      switch input.body {
      case .json(let payload): payload.description
      }
    try await persistence.create(
      .room(
        .init(
          id: id,
          createdAt: .init(),
          name: name,
          description: description
        )
      )
    )
    return .ok(
      .init(
        body: .json(
          .init(
            id: id.uuidString,
            name: name,
            description: description
          )
        )
      )
    )
  }
}
