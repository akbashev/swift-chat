import API
import Persistence

import struct Foundation.UUID

/// Implementation of OpenAPI `APIProtocol` for backend
struct Api: APIProtocol {

  let clientServerConnectionHandler: ClientServerConnectionHandler
  let persistence: Persistence

  func getMessages(
    _ input: Operations.getMessages.Input
  ) async throws
    -> Operations.getMessages.Output
  {
    let eventStream = try await self.clientServerConnectionHandler.getStream(info: input)
    let chosenContentType =
      input.headers.accept.sortedByQuality().first ?? .init(contentType: .application_jsonl)
    let responseBody: Operations.getMessages.Output.Ok.Body =
      switch chosenContentType.contentType {
      case .application_jsonl:
        .application_jsonl(
          .init(eventStream.asEncodedJSONLines(), length: .unknown, iterationBehavior: .single)
        )
      case .other:
        throw Frontend.Error.unsupportedType
      }
    return .ok(.init(body: responseBody))
  }

  func searchRoom(
    _ input: API.Operations.searchRoom.Input
  ) async throws
    -> API.Operations.searchRoom.Output
  {
    let rooms =
      try await persistence
      .searchRoom(query: input.query.query)
      .map {
        Components.Schemas.RoomResponse(
          id: $0.id.uuidString,
          name: $0.name,
          description: $0.description
        )
      }
    return .ok(.init(body: .json(rooms)))
  }

  func createUser(
    _ input: API.Operations.createUser.Input
  ) async throws
    -> API.Operations.createUser.Output
  {
    guard
      let name =
        switch input.body {
        case .json(let payload): payload.name
        }
    else {
      throw Frontend.Error.noConnection
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

  func createRoom(_ input: Operations.createRoom.Input) async throws -> Operations.createRoom.Output {
    guard
      let name =
        switch input.body {
        case .json(let payload): payload.name
        }
    else {
      throw Frontend.Error.noConnection
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
