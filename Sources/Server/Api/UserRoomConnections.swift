import Foundation
import API
import OpenAPIHummingbird
import OpenAPIRuntime
import Backend
import DistributedCluster
import Persistence

actor UserRoomConnections {
  
  typealias Value = Components.Schemas.ChatMessage
  static let heartbeatInterval: Duration = .seconds(15)
  
  let actorSystem: ClusterSystem
  let persistence: Persistence
  var connections: [Key: Connection] = [:]

  func addConnectionFor(
    userId: String,
    roomId: String,
    inputStream: AsyncThrowingMapSequence<JSONLinesDeserializationSequence<HTTPBody>, Value>,
    continuation: AsyncStream<Value>.Continuation
  ) async throws {
    let key = try Key(
      userId: userId,
      roomId: roomId
    )
    // TODO: Handle properly when connection is already there
    if self.connections[key] != nil {
      self.removeConnectionFor(key: key)
    }
    
    let room = try await self.findRoom(with: key)
    let userModel = try await persistence
      .getUser(id: key.userId)
    let user = User(
      actorSystem: self.actorSystem,
      userInfo: .init(
        id: userModel.id,
        name: userModel.name
      ),
      reply: { messages in
        for output in messages {
          let value = switch output {
          case let .message(messageInfo):
            Value(
              user: .init(
                id: messageInfo.userInfo.id.rawValue.uuidString,
                name: messageInfo.userInfo.name
              ),
              room: .init(
                id: messageInfo.roomInfo.id.rawValue.uuidString,
                name: messageInfo.roomInfo.name,
                description: messageInfo.roomInfo.description
              ),
              message: .init(messageInfo.message)
            )
          }
          continuation.yield(value)
        }
      }
    )
    let connection = Connection(
      user: user,
      room: room,
      continuation: continuation,
      listener: self.listenForMessages(
        in: inputStream,
        key: key
      )
    )
    self.connections[key] = connection
    connection.send(message: .join)
    continuation.onTermination = { _ in
      Task { [weak self] in
        try await self?.removeConnectionFor(
          userId: userId,
          roomId: roomId
        )
      }
    }
  }
  
  private func listenForMessages(
    in inputStream: AsyncThrowingMapSequence<JSONLinesDeserializationSequence<HTTPBody>, Value>,
    key: Key
  ) -> Task<Void, Swift.Error> {
    Task { [weak self] in
      for try await message in inputStream {
        guard !Task.isCancelled else { return }
        try? await self?.handleMessage(message)
      }
      await self?.removeConnectionFor(key: key)
    }
  }
  
  private func handleMessage(
    _ message: Value
  ) async throws {
    let userId = message.user.id
    let roomId = message.room.id
    let key = try Key(
      userId: userId,
      roomId: roomId
    )
    self.connections[key]?.latestMessageDate = Date()
    guard
      let connection = self.connections[key],
      let message: User.Message = .init(message.message)
    else { return }
    switch message {
    case .leave,
        .disconnect:
      try await connection.user.send(
        message: message,
        to: connection.room
      )
      connection.listener.cancel()
      self.connections.removeValue(forKey: key)
    default:
      do {
        try await connection.user.send(
          message: message,
          to: connection.room
        )
      } catch {
        self.removeConnectionFor(key: key)
        throw error
      }
    }
  }
  
  func checkConnections() {
    var connectionsToRemove: [Key] = []
    for (info, connection) in self.connections {
      if Date().timeIntervalSince(connection.latestMessageDate) > UserRoomConnections.heartbeatInterval.timeInterval {
        connectionsToRemove.append(info)
      }
    }
    for key in connectionsToRemove {
      self.removeConnectionFor(key: key)
    }
  }
  
  private func removeConnectionFor(
    userId: String,
    roomId: String
  ) throws {
    let key = try Key(
      userId: userId,
      roomId: roomId
    )
    self.removeConnectionFor(
      key: key
    )
  }
  
  private func removeConnectionFor(
    key: Key
  ) {
    guard let connection = self.connections[key] else { return }
    connection.send(message: .disconnect)
    connection.listener.cancel()
    self.connections.removeValue(forKey: key)
  }
  
  private func findRoom(
    with key: Key
  ) async throws -> Room {
    let roomModel = try await self.persistence.getRoom(id: key.roomId)
    return try await self.actorSystem.virtualActors.actor(
      id: key.roomId.uuidString,
      dependency: Room.Info(
        id: key.roomId,
        name: roomModel.name,
        description: roomModel.description
      )
    )
  }
  
  init(
    actorSystem: ClusterSystem,
    persistence: Persistence
  ) {
    self.actorSystem = actorSystem
    self.persistence = persistence
  }
}

extension Components.Schemas.ChatMessage.messagePayload {
  init(_ message: User.Message) {
    self = switch message {
    case .join:
      .JoinMessage(.init(_type: .join))
    case .message(let string, let at):
      .TextMessage(.init(_type: .message, content: string, timestamp: at))
    case .leave:
      .LeaveMessage(.init(_type: .leave))
    case .disconnect:
      .DisconnectMessage(.init(_type: .disconnect))
    }
  }
}

extension User.Message {
  init?(_ message: Components.Schemas.ChatMessage.messagePayload) {
    switch message {
    case .TextMessage(let message):
      self = .message(message.content, at: message.timestamp)
    case .JoinMessage:
      self = .join
    case .LeaveMessage:
      self = .leave
    case .DisconnectMessage:
      self = .disconnect
    case .HeartbeatMessage:
      return nil
    }
  }
}

extension UserRoomConnections {
  enum Error: Swift.Error {
    case parseError
  }
  
  struct Key: Hashable {
    let userId: UUID
    let roomId: UUID
  }
  
  struct Connection {
    let user: User
    let room: Room
    let continuation: AsyncStream<Value>.Continuation
    let listener: Task<Void, Swift.Error>
    var latestMessageDate: Date = Date()
    
    func send(message: User.Message) {
      Task { [weak user, weak room] in
        guard let user, let room else { return }
        do {
          try await user.send(message: message, to: room)
        } catch {
          // TODO: Retry mechanism?
          self.continuation.finish()
        }
      }
    }
  }
}

extension UserRoomConnections.Key {
  init(
    userId: String,
    roomId: String
  ) throws {
    guard
      let userId = UUID(uuidString: userId),
      let roomId = UUID(uuidString: roomId)
    else {
      throw UserRoomConnections.Error.parseError
    }
    self.userId = userId
    self.roomId = roomId
  }
}

extension Duration {
  var timeInterval: TimeInterval {
    let seconds = TimeInterval(self.components.seconds)
    let nanoseconds = TimeInterval(self.components.attoseconds) / 1_000_000_000_000_000
    return seconds + nanoseconds
  }
}
