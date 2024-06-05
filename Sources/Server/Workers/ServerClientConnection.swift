import Hummingbird
import Foundation
import Backend
import Persistence
import DistributedCluster
import PostgresNIO
import ServiceLifecycle
import API
import OpenAPIHummingbird
import OpenAPIRuntime

actor ServerClientConnection {
  
  typealias Value = Components.Schemas.ChatMessage

  private var streams: [String: Task<Void, any Error>] = [:]
  
  let userRoomConnections: UserRoomConnections
  let logger: Logger
  
  public init(
    actorSystem: ClusterSystem,
    persistence: Persistence,
    logger: Logger = Logger(label: "ServerClientConnection")
  ) {
    self.logger = logger
    self.userRoomConnections = .init(
      actorSystem: actorSystem,
      persistence: persistence
    )
  }

  func getStream(
    info: Operations.getMessages.Input
  ) -> AsyncStream<Value> {
    let userId = info.query.user_id
    let roomId = info.query.room_id
    let id = UUID().uuidString
    let (stream, continuation) = AsyncStream<Value>.makeStream()
    continuation.onTermination = { termination in
      Task { [weak self] in
        switch termination {
        case .cancelled: await self?.cancelStream(id: id)
        case .finished: await self?.finishedStream(id: id)
        @unknown default: await self?.finishedStream(id: id)
        }
      }
    }
    let task = Task<Void, any Error> { [weak self] in
      self?.logger.info(
        "add connection",
        metadata: [
          "userId": .string(userId),
          "roomId": .string(roomId)
        ]
      )
      
      do {
        try await self?.userRoomConnections.add(
          connection: continuation,
          userId: userId,
          roomId: roomId
        )
        for try await input in stream {
          try await self?.userRoomConnections.handleMessage(
            input
          )
        }
      } catch {
        self?.logger.log(level: .error, .init(stringLiteral: error.localizedDescription))
      }
      
      self?.logger.info(
        "remove connection",
        metadata: [
          "userId": .string(userId),
          "roomId": .string(roomId)
        ]
      )
      try? await self?.userRoomConnections.removeConnectionFor(
        userId: userId,
        roomId: roomId
      )
      continuation.finish()
    }
    streams[id] = task
    return stream
  }
  
  func handleMessage(
    _ input: Operations.sendMessage.Input
  ) async throws {
    switch input.body {
    case .json(let message):
      try await self.userRoomConnections.handleMessage(message)
    }
  }
  
  private func finishedStream(id: String) {
    guard self.streams[id] != nil else { return }
    self.streams.removeValue(forKey: id)
  }
  
  private func cancelStream(id: String) {
    guard let task = self.streams[id] else { return }
    self.streams.removeValue(forKey: id)
    task.cancel()
  }
}

actor UserRoomConnections {
  
  typealias Value = Components.Schemas.ChatMessage

  struct Info: Hashable {
    let userId: UUID
    let roomId: UUID
  }
  
  let actorSystem: ClusterSystem
  let persistence: Persistence
  var connections: [Info: (User, Room)] = [:]
  
  func add(
    connection: AsyncStream<Value>.Continuation,
    userId: String,
    roomId: String
  ) async throws {
    let info = try Info(
      userId: userId,
      roomId: roomId
    )
    guard self.connections[info] == nil else { return }
    let room = try await self.findRoom(with: info)
    let userModel = try await persistence.getUser(id: info.userId)
    let user: User = User(
      actorSystem: self.actorSystem,
      userInfo: .init(
        id: userModel.id,
        name: userModel.name
      ),
      reply: { messages in
        for output in messages {
          let value: Value = switch output {
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
          connection.yield(value)
        }
      }
    )
    try await user.send(message: .join, to: room)
    self.connections[info] = (user, room)
  }
  
  func removeConnectionFor(
    userId: String,
    roomId: String
  ) async throws {
    let info = try Info(
      userId: userId,
      roomId: roomId
    )
    guard let (user, room) = self.connections[info] else { return }
    try await user.send(message: .leave, to: room)
    self.connections.removeValue(forKey: info)
  }
  
  func handleMessage(
    _ message: Value
  ) async throws {
    let info = try Info(
      userId: message.user.id,
      roomId: message.room.id
    )
    guard let (user, room) = self.connections[info] else { return }
    let message: User.Message = .init(message.message)
    try await user.send(
      message: message,
      to: room
    )
  }
  
  private func findRoom(
    with info: Info
  ) async throws -> Room {
    let roomModel = try await self.persistence.getRoom(id: info.roomId)
    return try await self.actorSystem.virtualActors.actor(id: info.roomId.uuidString) { actorSystem in
      await Room(
        actorSystem: actorSystem,
        roomInfo: .init(
          id: info.roomId,
          name: roomModel.name,
          description: roomModel.description
        )
      )
    }
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
  init(_ message: Components.Schemas.ChatMessage.messagePayload) {
    self = switch message {
    case .TextMessage(let message):
        .message(message.content, at: message.timestamp)
    case .JoinMessage:
        .join
    case .LeaveMessage:
        .leave
    case .DisconnectMessage:
        .disconnect
    }
  }
}

extension UserRoomConnections {
  enum Error: Swift.Error {
    case parseError
  }
}

extension UserRoomConnections.Info {
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
