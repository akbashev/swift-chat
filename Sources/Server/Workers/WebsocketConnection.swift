import HummingbirdWSCore
import HummingbirdWebSocket
import Hummingbird
import Foundation
import Frontend
import Backend
import Persistence
import DistributedCluster
import PostgresNIO
import ServiceLifecycle

actor WebsocketConnection: WebsocketApi.ConnectionManager {
  
  let outboundCounnections: OutboundConnections
  let connectionStream: AsyncStream<WebsocketApi.Connection>
  let connectionContinuation: AsyncStream<WebsocketApi.Connection>.Continuation
  let logger: Logger
  
  public init(
    actorSystem: ClusterSystem,
    persistence: Persistence,
    logger: Logger = Logger(label: "WebSocketConnection")
  ) {
    self.logger = logger
    (self.connectionStream, self.connectionContinuation) = AsyncStream<WebsocketApi.Connection>.makeStream()
    self.outboundCounnections = OutboundConnections(
      actorSystem: actorSystem,
      persistence: persistence
    )
  }
  
  func run() async {
    await withGracefulShutdownHandler {
      await withDiscardingTaskGroup { group in
        for await connection in self.connectionStream {
          group.addTask {
            self.logger.info(
              "add connection",
              metadata: [
                "userId": .string(connection.info.userId.uuidString),
                "roomId": .string(connection.info.roomId.uuidString)
              ]
            )
            
            do {
              try await self.outboundCounnections.add(
                connection: connection
              )
              for try await input in connection.inbound.messages(maxSize: 1_000_000) {
                try await self.outboundCounnections.handle(input, from: connection)
              }
            } catch {
              self.logger.log(level: .error, .init(stringLiteral: error.localizedDescription))
            }
            
            self.logger.info(
              "remove connection",
              metadata: [
                "userId": .string(connection.info.userId.uuidString),
                "roomId": .string(connection.info.roomId.uuidString)
              ]
            )
            try? await self.outboundCounnections.remove(
              connection: connection
            )
            connection.outbound.finish()
          }
        }
        group.cancelAll()
      }
    } onGracefulShutdown: {
      self.connectionContinuation.finish()
    }
  }
  
  func add(
    info: WebsocketApi.Connection.Info,
    inbound: WebSocketInboundStream,
    outbound: WebSocketOutboundWriter
  ) -> WebsocketApi.ConnectionManager.OutputStream {
    let outputStream = WebsocketApi.ConnectionManager.OutputStream()
    let connection = WebsocketApi.Connection(info: info, inbound: inbound, outbound: outputStream)
    self.connectionContinuation.yield(connection)
    return outputStream
  }
}

fileprivate extension ChatResponse.Message {
  init(_ message: User.Message) {
    self = switch message {
    case .join: .join
    case .message(let string, let date): .message(string, at: date)
    case .leave: .leave
    case .disconnect: .disconnect
    }
  }
}

fileprivate extension User.Message {
  init(_ message: ChatResponse.Message) {
    self = switch message {
    case .join: .join
    case .message(let string, let date): .message(string, at: date)
    case .leave: .leave
    case .disconnect: .disconnect
    }
  }
}

fileprivate extension UserResponse {
  init(_ userInfo: User.Info) {
    self.init(
      id: userInfo.id.rawValue,
      name: userInfo.name
    )
  }
}

fileprivate extension UserResponse {
  init(_ userModel: UserModel) {
    self.init(
      id: userModel.id,
      name: userModel.name
    )
  }
}


fileprivate extension RoomResponse {
  init(_ roomInfo: Room.Info) {
    self.init(
      id: roomInfo.id.rawValue,
      name: roomInfo.name,
      description: roomInfo.description
    )
  }
}

actor OutboundConnections {
  
  let actorSystem: ClusterSystem
  let persistence: Persistence
  var outboundWriters: [WebsocketApi.Connection.Info: (User, Room, WebsocketApi.ConnectionManager.OutputStream)] = [:]

  func handle(
    _ message: WebSocketMessage,
    from connection: WebsocketApi.Connection
  ) async throws {
    guard let (user, room, outbound) = self.outboundWriters[connection.info] else { return }
    switch message {
    case .text(let string):
      let createdAt = Date()
      try await user.send(
        message: .message(string, at: createdAt),
        to: room
      )
      var data = ByteBuffer()
      _ = try? await data.writeJSONEncodable(
        MessageInfo(
          roomInfo: room.info,
          userInfo: user.info,
          message: .message(string, at: createdAt)
        )
      )
      await outbound.send(.binary(data))
    case .binary(var data):
      guard let messages = try? data.readJSONDecodable(
        [ChatResponse.Message].self,
        length: data.readableBytes
      ) else { break }
      for message in messages {
        try await user.send(
          message: .init(message),
          to: room
        )
        var data = ByteBuffer()
        _ = try? await data.writeJSONEncodable(
          MessageInfo(
            roomInfo: room.info,
            userInfo: user.info,
            message: .init(message)
          )
        )
        await outbound.send(.binary(data))
      }
    }
  }
  
  func add(
    connection: WebsocketApi.Connection
  ) async throws {
    let room = try await self.findRoom(with: connection.info)
    let userModel = try await persistence.getUser(id: connection.info.userId)
    let user: User = User(
      actorSystem: self.actorSystem,
      userInfo: .init(
        id: userModel.id,
        name: userModel.name
      ),
      reply: { messages in
        let response: [ChatResponse] = messages.map { (output: User.Output) -> ChatResponse in
          switch output {
          case let .message(messageInfo):
            return ChatResponse(
              user: .init(messageInfo.userInfo),
              message: .init(messageInfo.message)
            )
          }
        }
        var data = ByteBuffer()
        _ = try? data.writeJSONEncodable(response)
        await connection.outbound.send(.binary(data))
      }
    )
    try await user.send(message: .join, to: room)
    self.outboundWriters[connection.info] = (user, room, connection.outbound)
  }
  
  func remove(
    connection: WebsocketApi.Connection
  ) async throws {
    guard let (user, room, outbound) = self.outboundWriters[connection.info] else { return }
    try await user.send(message: .leave, to: room)
    self.outboundWriters.removeValue(forKey: connection.info)
  }
  
  private func findRoom(
    with info: WebsocketApi.Connection.Info
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
