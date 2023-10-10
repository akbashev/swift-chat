import HummingbirdWSCore
import HummingbirdWebSocket
import HummingbirdFoundation
import FoundationEssentials
import Frontend
import Backend
import Persistence
import EventSource
import DistributedCluster
import PostgresNIO

public actor WebsocketConnection {
  
  private let persistence: Persistence
  private let roomInfo: RoomInfo
  private let userInfo: UserInfo
  private let room: Room
  private let user: User
  private let ws: HBWebSocket
  private var listeningTask: Task<Void, Error>?

  init(
    actorSystem: ClusterSystem,
    persistence: Persistence,
    eventSource: EventSource<MessageInfo>,
    roomPool: RoomPool,
    info: WebsocketApi.Event.Info
  ) async throws {
    self.persistence = persistence
    let roomModel = try await persistence.getRoom(id: info.roomId)
    let roomInfo = RoomInfo(
      id: roomModel.id,
      name: roomModel.name,
      description: roomModel.description
    )
    self.roomInfo = roomInfo
    self.room = try await roomPool.findRoom(
      with: roomInfo,
      eventSource: eventSource
    )
    let userModel = try await persistence.getUser(id: info.userId)
    let userInfo = UserInfo(
      id: userModel.id,
      name: userModel.name
    )
    self.userInfo = userInfo
    self.ws = info.ws
    self.user = try await User(
      actorSystem: actorSystem,
      userInfo: userInfo,
      reply: .init { output in
        /// 3. Start listening for messages from other users
        switch output {
        case let .message(message, userInfo, _):
          var data = ByteBuffer()
          _ = try? data.writeJSONEncodable([message])
          _ = info.ws.write(.binary(data))
        }
      }
    )
    self.start(ws: info.ws)
  }
  
  func start(ws: HBWebSocket) {
    Task {
      await self.sendOldMessages()
      try? await self.greeting()
      self.listenFor(messages: ws.readStream())
    }
  }
  
  func close() async {
    _ = try? await self.user.send(message: .disconnect, to: self.room)
  }
  
  func sendOldMessages() async {
    /// 5. Fetch all current room messages
    let messages = (try? await room.getMessages()) ?? []
    let users = await withTaskGroup(of: UserModel?.self) { group in
      for message in messages {
        switch message.message {
        case .message:
          group.addTask {
            try? await self.persistence.getUser(id: message.userId.rawValue)
          }
        default:
          break
        }
      }
      return await group
        .reduce(into: [UserModel]()) { partialResult, response in
          guard let response else { return }
          partialResult.append(response)
        }
    }
    let responses = messages.compactMap { message -> ChatResponse? in
      switch message.message {
      case .message(let text):
        guard
          let userModel = users
            .first(where: { $0.id == message.userId.rawValue })
        else { return .none }
        return ChatResponse(
          createdAt: message.createdAt,
          user: .init(userModel),
          message: .init(.message(text))
        )
      default:
        return .none
      }
    }
    self.send(messages: responses)
  }
  
  func greeting() async throws {
    let messageInfo = try await user.send(message: .join, to: room)
    self.send(
      message: ChatResponse(
        createdAt: messageInfo.createdAt,
        user: .init(self.userInfo),
        message: .init(messageInfo.message)
      )
    )
  }

  /// 6. Join to the Room and start sending user messages
  private func listenFor(
    messages: AsyncStream<WebSocketData>
  ) {
    self.listeningTask = Task {
      for await message in messages {
        guard !Task.isCancelled else { return }
        switch message {
        case .text(let string):
          try await self.send(
            response: user.send(
              message: .message(string),
              to: self.room
            )
          )
          break
        case .binary(var data):
          guard let messages = try data.readJSONDecodable(
            [ChatResponse.Message].self,
            length: data.readableBytes
          ) else { break }
          for message in messages {
            try await self.send(
              response: user.send(
                message: .init(message),
                to: self.room
              )
            )
          }
        }
      }
    }
  }
  
  func close() {
    self.listeningTask?.cancel()
    self.listeningTask = .none
    Task {
      try await self.ws.close()
    }
  }
  
  func send(response: MessageInfo) {
    self.send(responses: [response])
  }
  
  func send(responses: [MessageInfo]) {
    self.send(
      messages: responses.map {
        ChatResponse(
          createdAt: $0.createdAt,
          user: .init(self.userInfo),
          message: .init($0.message)
        )
      }
    )
  }
  
  func send(message: ChatResponse) {
    self.send(messages: [message])
  }
  
  func send(messages: [ChatResponse]) {
    var data = ByteBuffer()
    _ = try? data.writeJSONEncodable(messages)
    _ = self.ws.write(.binary(data))
  }
  
  deinit {
    print("deinit")
  }
}

extension MessageInfo: PostgresCodable {}

fileprivate extension ChatResponse.Message {
  init(_ message: Backend.Message) {
    switch message {
    case .join:
      self = .join
    case .message(let string):
      self = .message(string)
    case .leave:
      self = .leave
    case .disconnect:
      self = .disconnect
    }
  }
}

fileprivate extension Backend.Message {
  init(_ message: ChatResponse.Message) {
    switch message {
    case .join:
      self = .join
    case .message(let string):
      self = .message(string)
    case .leave:
      self = .leave
    case .disconnect:
      self = .disconnect
    }
  }
}

fileprivate extension UserResponse {
  init(_ userInfo: UserInfo) {
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
  init(_ roomInfo: RoomInfo) {
    self.init(
      id: roomInfo.id.rawValue,
      name: roomInfo.name,
      description: roomInfo.description
    )
  }
}
