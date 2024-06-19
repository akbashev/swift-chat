import Foundation
import Dependencies
import OpenAPIRuntime
import API

public actor ChatClient {
  
  public typealias Message = Components.Schemas.ChatMessage
  public struct Info: Hashable {
    let room: RoomPresentation
    let user: UserPresentation
  }
  
  @Dependency(\.client) var client
  var connections: [Info: AsyncStream<Message>.Continuation] = [:]
  
  public init() {
    self.heartbeat()
  }
  
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
    let info = Info(
      room: room,
      user: user
    )
    self.connections[info] = continuation
    continuation.onTermination = { termination in
      Task { [weak self] in await self?.removeConnection(info: info) }
    }
    return messageStream
  }
  
  public func send(message: Message, from user: UserPresentation, to room: RoomPresentation) throws {
    let info = Info(
      room: room,
      user: user
    )
    guard let connection = self.connections[info] else {
      // TODO: Should throw and handle
      return
    }
    connection.yield(message)
  }
  
  public func disconnect(
    user: UserPresentation,
    from room: RoomPresentation
  ) {
    let info = Info(
      room: room,
      user: user
    )
    self.connections[info]?.yield(
      .init(
        user: user,
        room: room,
        message: .disconnect
      )
    )
    self.removeConnection(info: info)
  }
  
  private func removeConnection(info: Info) {
    self.connections.removeValue(forKey: info)
  }
  
  private var heartbeatTask: Task<Void, Never>?
  private func heartbeat() {
    let heartbeatSequence = HeartbeatSequence()
    self.heartbeatTask = Task {
      for await message in heartbeatSequence {
        for (info, connection) in self.connections {
          connection.yield(
            Message(
              user: info.user,
              room: info.room,
              message: message
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

struct HeartbeatSequence: AsyncSequence {
  
  typealias Element = Components.Schemas.HeartbeatMessage
  
  struct AsyncIterator: AsyncIteratorProtocol {
    mutating func next() async -> Components.Schemas.HeartbeatMessage? {
      try? await Task.sleep(for: .seconds(10))
      return .init(_type: .heartbeat)
    }
  }
  
  func makeAsyncIterator() -> AsyncIterator {
    return AsyncIterator()
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
