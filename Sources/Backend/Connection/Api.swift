import AsyncAlgorithms
import AuthCore
import Foundation
import HummingbirdCore
import HummingbirdWebSocket
import Models
import OpenAPIRuntime
import Persistence
import ServiceLifecycle
import WSCore

/// Implementation of OpenAPI `APIProtocol` for backend
public struct Api: APIProtocol {

  enum Error: Swift.Error {
    case noConnection
    case noDatabaseAvailable
    case unsupportedType
    case alreadyConnected
    case unexpectedServerError
  }

  let participantRoomConnections: ParticipantRoomConnections
  let persistence: Persistence
  let heartbeatSequence = AsyncTimerSequence(
    interval: .seconds(15),
    clock: .continuous
  )

  public init(
    participantRoomConnections: ParticipantRoomConnections,
    persistence: Persistence
  ) {
    self.participantRoomConnections = participantRoomConnections
    self.persistence = persistence
  }

  public func getMessages(
    _ input: Operations.GetMessages.Input
  ) async throws
    -> Operations.GetMessages.Output
  {
    guard
      let participantId = UUID(uuidString: input.headers.participantId),
      let roomId = UUID(uuidString: input.headers.roomId)
    else {
      throw Api.Error.unsupportedType
    }

    let inputStream =
      switch input.body {
      case .applicationJsonl(let body):
        body.asDecodedJSONLines(
          of: ChatMessage.self
        )
      }
    let request = ParticipantRoomConnections.Connection.RequestParameter(
      participantId: participantId,
      roomId: roomId
    )
    let outputStream = try await self.participantRoomConnections.addJSONLConnectionFor(
      request: request,
      inbound: inputStream
    )

    let messageStream = AsyncThrowingStream<ChatMessage, Swift.Error> { continuation in
      let listener = Task {
        for try await output in outputStream {
          switch output {
          case .response(let message):
            continuation.yield(message)
          case .close(_):
            continuation.finish()
          }
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        listener.cancel()
        Task {
          try await self.participantRoomConnections.removeJSONLConnectionFor(request: request)
        }
      }
    }

    let heartbeatStream = self.heartbeatSequence
      .map { _ in ChatMessage.heartbeat }

    let eventStream = merge(messageStream, heartbeatStream)
    let chosenContentType =
      input.headers.accept.sortedByQuality().first ?? .init(contentType: .applicationJsonl)
    let responseBody: Operations.GetMessages.Output.Ok.Body =
      switch chosenContentType.contentType {
      case .applicationJsonl:
        .applicationJsonl(
          .init(
            eventStream.asEncodedJSONLines(),
            length: .unknown,
            iterationBehavior: .single
          )
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

  public func register(
    _ input: Operations.Register.Input
  ) async throws -> Operations.Register.Output {
    guard
      let name =
        switch input.body {
        case .json(let payload): payload.name
        }
    else {
      throw Api.Error.noConnection
    }
    guard
      let password =
        switch input.body {
        case .json(let payload): payload.password
        }
    else {
      throw Api.Error.noConnection
    }
    let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPassword.isEmpty else {
      throw Api.Error.noConnection
    }
    let id = UUID()
    do {
      _ = try await persistence.getParticipantAuth(named: name)
      return .conflict(.init())
    } catch Persistence.Error.participantMissing {
      let passwordHash = try await PasswordHasher.hash(trimmedPassword)
      try await persistence.create(
        .participant(
          .init(
            id: id,
            createdAt: .init(),
            name: name,
            passwordHash: passwordHash
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

  public func login(
    _ input: Operations.Login.Input
  ) async throws -> Operations.Login.Output {
    guard
      let name =
        switch input.body {
        case .json(let payload): payload.name
        }
    else {
      throw Api.Error.noConnection
    }
    guard
      let password =
        switch input.body {
        case .json(let payload): payload.password
        }
    else {
      throw Api.Error.noConnection
    }
    let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPassword.isEmpty else {
      throw Api.Error.noConnection
    }
    do {
      let auth = try await persistence.getParticipantAuth(named: name)
      let matches = try await PasswordHasher.verify(trimmedPassword, hash: auth.passwordHash)
      guard matches else {
        return .unauthorized(.init())
      }
      return .ok(
        .init(
          body: .json(
            .init(
              id: auth.participant.id.uuidString,
              name: auth.participant.name
            )
          )
        )
      )
    } catch {
      return .unauthorized(.init())
    }
  }

  public func shouldUpgrade(
    request: Request,
    context: BasicWebSocketRequestContext
  ) async throws -> RouterShouldUpgrade {
    // only allow upgrade if participantname query parameter exists
    guard
      request.uri.queryParameters["participant_id"] != nil,
      request.uri.queryParameters["room_id"] != nil
    else {
      return .dontUpgrade
    }
    return .upgrade([:])
  }

  public func onUpgrade(
    inbound: WebSocketInboundStream,
    outbound: WebSocketOutboundWriter,
    context: WebSocketRouterContext<BasicWebSocketRequestContext>
  ) async throws {
    let participantId = try context.request.uri.queryParameters.require("participant_id", as: UUID.self)
    let roomId = try context.request.uri.queryParameters.require("room_id", as: UUID.self)
    let parameters = ParticipantRoomConnections.Connection.RequestParameter(
      participantId: participantId,
      roomId: roomId
    )
    do {
      let outputStream = try await self.participantRoomConnections.addWSConnectionFor(
        request: parameters,
        inbound: inbound
      )
      for try await output in outputStream {
        switch output {
        case .frame(let frame):
          try await outbound.write(frame)
        case .close(let reason):
          try await outbound.close(.unexpectedServerError, reason: reason)
        }
      }
    } catch {
      try await outbound.close(.unexpectedServerError, reason: error.localizedDescription)
    }
  }
}

extension ChatMessage {
  fileprivate static var heartbeat: ChatMessage {
    // TODO: think metadata doesn't matter, but double check
    ChatMessage(
      participant: .init(id: "", name: ""),
      room: .init(id: "", name: ""),
      message: .HeartbeatMessage(.init(heartbeatAt: Date()))
    )
  }
}
