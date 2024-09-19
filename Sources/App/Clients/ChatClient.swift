import Foundation
import Dependencies
import OpenAPIRuntime
import API
import AsyncAlgorithms

public actor ChatClient {
  
  public typealias Message = Components.Schemas.ChatMessage
  private static let heartbeatInterval: Duration = .seconds(10)

  @Dependency(\.client) var client
  private var connections: [Key: AsyncStream<Message>.Continuation] = [:]
  private let heartbeatSequence = AsyncTimerSequence(
    interval: ChatClient.heartbeatInterval,
    clock: .continuous
  )
  
  public init() {}

  public func connect(
    user: UserPresentation,
    to room: RoomPresentation
  ) async throws -> AsyncThrowingMapSequence<JSONLinesDeserializationSequence<HTTPBody>, Message> {
    let (stream, continuation) = AsyncStream<Components.Schemas.ChatMessage>.makeStream()
    let headers = Operations.getMessages.Input.Headers(
      user_id: user.id.uuidString,
      room_id: room.id.uuidString
    )
    let body: Operations.getMessages.Input.Body = .application_jsonl(
      .init(
        stream.asEncodedJSONLines(),
        length: .unknown,
        iterationBehavior: .single
      )
    )
    let response = try await self.client.getMessages(
      headers: headers,
      body: body
    )
    let messageStream = try response.ok.body.application_jsonl.asDecodedJSONLines(
      of: Message.self
    )
    let key = Key(
      room: room,
      user: user
    )
    self.connections[key] = continuation
    continuation.onTermination = { termination in
      Task { [weak self] in await self?.removeConnection(for: key) }
    }
    if heartbeatTask == .none {
      self.heartbeat()
    }
    return messageStream
  }
  
  public func send(message: Message, from user: UserPresentation, to room: RoomPresentation) throws {
    let key = Key(
      room: room,
      user: user
    )
    guard let connection = self.connections[key] else {
      throw Error.connectionMissing
    }
    connection.yield(message)
  }
  
  public func disconnect(
    user: UserPresentation,
    from room: RoomPresentation
  ) {
    let key = Key(
      room: room,
      user: user
    )
    self.connections[key]?.yield(
      .init(
        user: user,
        room: room,
        message: .disconnect
      )
    )
    self.removeConnection(for: key)
  }
  
  private func removeConnection(for key: Key) {
    self.connections.removeValue(forKey: key)
    if self.connections.isEmpty {
      self.heartbeatTask?.cancel()
      self.heartbeatTask = .none
    }
  }
  
  private var heartbeatTask: Task<Void, Never>?
  private func heartbeat() {
    self.heartbeatTask = Task {
      for await _ in heartbeatSequence {
        for (info, connection) in self.connections {
          connection.yield(
            Message(
              user: info.user,
              room: info.room,
              message: .init(_type: .heartbeat)
            )
          )
        }
      }
    }
  }
  
  deinit {
    self.heartbeatTask?.cancel()
  }
}

extension ChatClient {
  public enum Error: Swift.Error {
    case connectionMissing
  }
  
  public struct Key: Hashable, Sendable {
    let room: RoomPresentation
    let user: UserPresentation
  }
}

extension ChatClient: DependencyKey {
  public static let liveValue: ChatClient = ChatClient()
}

extension DependencyValues {
  var chatClient: ChatClient {
    get { self[ChatClient.self] }
    set { self[ChatClient.self] = newValue }
  }
}
