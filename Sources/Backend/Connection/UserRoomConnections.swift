import AsyncAlgorithms
import DistributedCluster
import Foundation
import Hummingbird
import HummingbirdWebSocket
import Logging
import Models
import OpenAPIRuntime
import Persistence
import ServiceLifecycle
import VirtualActors

// TODO: Cleanup file
public struct ParticipantRoomConnections: Service {

  public enum Connection: Identifiable, Sendable {
    case jsonl(JSONLConnection)
    case websocket(WebSocketConnection)

    public var id: String {
      switch self {
      case .jsonl(let connection): connection.id
      case .websocket(let connection): connection.id
      }
    }

    func send(message: Room.Message) async throws {
      switch self {
      case .jsonl(let connection):
        try await connection.send(message: message)
      case .websocket(let connection):
        try await connection.send(message: message)
      }
    }

    func finish() {
      switch self {
      case .jsonl(let connection):
        connection.outbound.finish()
      case .websocket(let connection):
        connection.outbound.finish()
      }
    }
  }

  /// An actor is used to manage the outbound connections in a thread safe manner
  /// This is required because the websocket connection can be opened and closed on different threads
  ///
  /// In a production setting, you would also want to use an event broker like Redis or Kafka of sorts.
  /// That way, you can horizontally scale your application by adding more instances of this service.
  actor OutboundConnections {

    enum Error: Swift.Error {
      case alreadyAdded
      case leaving
      case missingConnection
      case missingConversation
    }

    private var connections: [Connection.ID: Connection] = [:]
    private let logger: Logger

    func add(
      _ connection: Connection
    ) async throws {
      if self.connections[connection.id] != nil {
        self.logger.info("participant already exists", metadata: ["conversationId": .string(connection.id)])
        // remove and reconnect
        try await self.remove(connectionWithId: connection.id)
      }

      self.connections[connection.id] = connection
      do {
        try await self.send(.join(Date()), to: connection.id)
      } catch Room.Error.participantAlreadyJoined {
        // TODO: Handle it
      } catch {
        throw error
      }
    }

    func remove(_ connection: Connection) async throws {
      try await self.remove(connectionWithId: connection.id)
    }

    func remove(connectionWithId id: Connection.ID) async throws {
      defer {
        self.connections[id] = nil
      }
      do {
        try await self.send(.disconnect(Date()), to: id)
      } catch Room.Error.participantIsMissing {
        // TODO: Handle it
      } catch {
        throw error
      }
    }

    func send(_ message: Room.Message, to id: Connection.ID) async throws {
      guard let connection = self.connections[id] else {
        throw OutboundConnections.Error.missingConnection
      }
      try await connection.send(message: message)
    }

    init(logger: Logger) {
      self.logger = logger
    }
  }

  /// A stream of new connections being accepted by the server
  let connectionStream: AsyncStream<Connection>
  /// A continuation for the connection stream, that can emit new signals
  private let connectionContinuation: AsyncStream<Connection>.Continuation
  /// A logger for the connection manager
  let logger: Logger
  let actorSystem: ClusterSystem
  /// Encoder/Decoder
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()
  /// Persistence
  let persistence: Persistence
  // The OutboundConnections actor is used to manage the outbound connections in a thread safe manner
  // Allowing us to broadcast messages to all the connected clients
  let outboundConnections: OutboundConnections

  public func run() async {
    /// The `withGracefulShutdownHandler` is a helper that will call the `onGracefulShutdown` closure
    /// when the application is shutting down.
    ///
    /// This helps ensure that the application will not exit before the connection manager has a chance to
    /// clean up all the connections.
    await withGracefulShutdownHandler {
      /// The `withDiscardingTaskGroup` is a task group that can indefinitely add tasks to it.
      /// As opposed to a regular task group, it will not incur memory overhead for each task added.
      /// This allows it to scale for a large number of tasks.
      await withDiscardingTaskGroup { group in
        // As each client connects, the for loop will emit the next connection
        for await connection in self.connectionStream {
          // Each client connection is handled in a new task, so their work is parallelized
          group.addTask {
            self.logger.info(
              "add connection",
              metadata: ["conversationId": .string(connection.id)]
            )

            do {
              // Add the client to the list of connected clients
              try await self.outboundConnections.add(connection)
              try await self.handleMessages(from: connection)
            } catch {
              self.logger.error(Logger.Message(stringLiteral: error.localizedDescription))
            }
            // When the connection is closed, we remove the client from the list of connected clients
            self.logger.info("remove connection", metadata: ["conversationId": .string(connection.id)])
            try? await self.outboundConnections.remove(connection)
            connection.finish()
          }
        }

        // Once the server is shutting down, the for loop will finish
        // This leads to this line, where we cancel all the tasks in the task group
        // The cancellation will in turn close the `messages` iterator for each connection
        // That will ca                                                                          use all connections to be cleaned up, allowing the application to exit
        group.cancelAll()
      }
    } onGracefulShutdown: {
      /// Closes the connection stream, which will stop the server from handling new connections
      self.connectionContinuation.finish()
    }
  }

  private func handleMessages(from connection: Connection) async throws {
    switch connection {
    case .websocket(let webSocketConnection):

      // We handle the stream as incoming messages emitted by this client
      // The `for try await` loop will suspend until a new message is available
      // Once a message is available, the message is handled before awaiting the next one
      // This implicitly applies "backpressure" to the client, to prevent it from sending too many messages
      // which would've otherwise overwhelmed the server
      for try await input in webSocketConnection.inbound.messages(maxSize: 1_000_000) {
        // We only handle text messages
        switch input {
        case .binary(let byteBuffer):
          guard
            let data = Data(byteBuffer: byteBuffer),
            let messageEnvelope = try? self.decoder.decode(ChatMessage.self, from: data),
            let message = Room.Message(messageEnvelope.message)
          else { return }
          self.logger.debug("Output", metadata: ["message": .string("\(messageEnvelope)")])
          try await self.outboundConnections.send(message, to: connection.id)
        default:
          break
        }
      }
    case .jsonl(let jsonlConnection):
      // We handle the stream as incoming messages emitted by this client
      // The `for try await` loop will suspend until a new message is available
      // Once a message is available, the message is handled before awaiting the next one
      // This implicitly applies "backpressure" to the client, to prevent it from sending too many messages
      // which would've otherwise overwhelmed the server
      for try await message in jsonlConnection.inbound {
        guard let roomMessage = Room.Message(message.message) else { continue }
        try await self.outboundConnections.send(roomMessage, to: connection.id)
      }
    }
  }

  private func findRoom(
    for parameters: ParticipantRoomConnections.Connection.RequestParameter
  ) async throws -> Backend.Room {
    let model = try await self.persistence.getRoom(for: parameters.roomId)
    return try await self.actorSystem.virtualActors.getActor(
      identifiedBy: .init(rawValue: parameters.roomId.uuidString),
      dependency: Backend.Room.Info(
        id: parameters.roomId,
        name: model.name,
        description: model.description
      )
    )
  }

  public init(
    actorSystem: ClusterSystem,
    logger: Logger,
    persistence: Persistence
  ) {
    self.actorSystem = actorSystem
    self.logger = logger
    (self.connectionStream, self.connectionContinuation) = AsyncStream<Connection>.makeStream()
    self.persistence = persistence
    self.outboundConnections = OutboundConnections(logger: logger)
  }

}

extension ParticipantRoomConnections {

  public func addWSConnectionFor(
    request: ParticipantRoomConnections.Connection.RequestParameter,
    inbound: WebSocketInboundStream
  ) async throws -> Connection.WebSocketConnection.OutputStream {
    let outbound = Connection.WebSocketConnection.OutputStream()
    let room = try await self.findRoom(for: request)
    let participantModel =
      try await persistence
      .getParticipant(for: request.participantId)
    let participant = Participant(
      actorSystem: self.actorSystem,
      info: .init(
        id: participantModel.id,
        name: participantModel.name
      ),
      reply: { [weak outbound] messages in
        let responses: [ChatMessage] = messages.map {
          switch $0 {
          case let .message(envelope):
            ChatMessage(
              participant: .init(
                id: envelope.participant.id.rawValue.uuidString,
                name: envelope.participant.name
              ),
              room: .init(
                id: envelope.room.id.rawValue.uuidString,
                name: envelope.room.name,
                description: envelope.room.description
              ),
              message: .init(envelope.message)
            )
          }
        }
        let data = try self.encoder.encode(responses)
        await outbound?.send(.frame(.binary(ByteBuffer(data: data))))
      }
    )
    let connection = Connection.websocket(
      .init(
        requestParameter: request,
        participant: participant,
        room: room,
        inbound: inbound,
        outbound: outbound
      )
    )
    self.connectionContinuation.yield(connection)
    return outbound
  }

  public func addJSONLConnectionFor(
    request: ParticipantRoomConnections.Connection.RequestParameter,
    inbound: AsyncThrowingMapSequence<JSONLinesDeserializationSequence<HTTPBody>, ChatMessage>
  ) async throws -> Connection.JSONLConnection.OutputStream {
    let outbound = Connection.JSONLConnection.OutputStream()
    let room = try await self.findRoom(for: request)
    let participantModel =
      try await persistence
      .getParticipant(for: request.participantId)
    let participant = Participant(
      actorSystem: self.actorSystem,
      info: .init(
        id: participantModel.id,
        name: participantModel.name
      ),
      reply: { [weak outbound] messages in
        for message in messages {
          let response =
            switch message {
            case let .message(envelope):
              ChatMessage(
                participant: .init(
                  id: envelope.participant.id.rawValue.uuidString,
                  name: envelope.participant.name
                ),
                room: .init(
                  id: envelope.room.id.rawValue.uuidString,
                  name: envelope.room.name,
                  description: envelope.room.description
                ),
                message: .init(envelope.message)
              )
            }
          await outbound?.send(.response(response))
        }
      }
    )
    let connection = Connection.jsonl(
      .init(
        requestParameter: request,
        participant: participant,
        room: room,
        inbound: inbound,
        outbound: outbound
      )
    )
    self.connectionContinuation.yield(connection)
    return outbound
  }

  public func removeJSONLConnectionFor(
    request: ParticipantRoomConnections.Connection.RequestParameter
  ) async throws {
    try await self.outboundConnections.remove(connectionWithId: request.id)
  }
}

extension Data {
  init?(byteBuffer: ByteBuffer) {
    var buffer = byteBuffer
    guard
      let data = buffer.readData(
        length: buffer.readableBytes,
        byteTransferStrategy: .automatic
      )
    else { return nil }
    self = data
  }
}

extension ParticipantRoomConnections.Connection {

  public struct RequestParameter: Hashable, Identifiable, Sendable {
    public var id: String { "\(self.roomId.uuidString)_\(self.participantId.uuidString)" }
    public let participantId: UUID
    public let roomId: UUID

    public init(
      participantId: UUID,
      roomId: UUID
    ) {
      self.participantId = participantId
      self.roomId = roomId
    }
  }

  public struct JSONLConnection: Identifiable, Sendable {

    public enum Output: Sendable {
      case close(reason: String)
      case response(ChatMessage)
    }

    typealias InputStream = AsyncThrowingMapSequence<JSONLinesDeserializationSequence<HTTPBody>, ChatMessage>
    public typealias OutputStream = AsyncChannel<Output>

    public var id: String { self.requestParameter.id }
    let requestParameter: RequestParameter

    let participant: Participant
    let room: Room

    let inbound: InputStream
    let outbound: OutputStream

    func send(message: Room.Message) async throws {
      try await self.participant.send(message: message, to: self.room)
    }
  }

  public struct WebSocketConnection: Identifiable, Sendable {
    public enum Output: Sendable {
      case close(reason: String)
      case frame(WebSocketOutboundWriter.OutboundFrame)
    }
    public typealias OutputStream = AsyncChannel<Output>

    public var id: String { self.requestParameter.id }
    let requestParameter: RequestParameter

    let participant: Participant
    let room: Room

    let inbound: WebSocketInboundStream
    let outbound: OutputStream

    func send(message: Room.Message) async throws {
      try await self.participant.send(message: message, to: self.room)
    }
  }
}

extension ChatMessage.MessagePayload {
  init(_ message: Backend.Room.Message) {
    self =
      switch message {
      case .join(let date):
        .JoinMessage(.init(joinedAt: date))
      case .message(let string, let at):
        .TextMessage(.init(content: string, timestamp: at))
      case .disconnect(let date):
        .DisconnectMessage(.init(disconnectedAt: date))
      }
  }
}

extension Backend.Room.Message {
  init?(_ message: ChatMessage.MessagePayload) {
    switch message {
    case .TextMessage(let message):
      self = .message(message.content, at: message.timestamp)
    case .JoinMessage(let value):
      self = .join(value.joinedAt)
    case .DisconnectMessage(let value):
      self = .disconnect(value.disconnectedAt)
    case .HeartbeatMessage:
      return nil
    }
  }
}
