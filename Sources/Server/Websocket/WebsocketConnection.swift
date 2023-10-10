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

actor WebsocketConnection {
  
  private let persistence: Persistence
  private let roomInfo: RoomInfo
  private let userInfo: UserInfo
  private let room: Room
  private let user: User
  private let ws: WebsocketApi.WebSocket
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
        /// Start listening for messages from other users
        switch output {
        case let .message(message, userInfo, _):
          let response = ChatResponse(
            createdAt: message.createdAt,
            user: .init(userInfo),
            message: .init(message.message)
          )
          info.ws.write([response])
        }
      }
    )
    self.start(ws: info.ws)
  }
  
  func start(ws: WebsocketApi.WebSocket) {
    self.listeningTask = Task {
      /// Join to the Room and start sending user messages
      await self.sendOldMessages()
      await self.join()
      await self.listenFor(messages: ws.read)
    }
  }
  
  func close() {
    self.listeningTask?.cancel()
    self.listeningTask = .none
    Task {
      _ = try? await self.user.send(message: .disconnect, to: self.room)
      try? await self.ws.close()
    }
  }
  
  /// Fetch all current room messages
  private func sendOldMessages() async {
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
    let responses = messages
      .compactMap { message -> ChatResponse? in
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
  
  private func join() async {
    do {
      let messageInfo = try await user.send(message: .join, to: room)
      self.send(
        message: ChatResponse(
          createdAt: messageInfo.createdAt,
          user: .init(self.userInfo),
          message: .init(messageInfo.message)
        )
      )
    } catch {
      self.close()
    }
  }
  
  private func listenFor(
    messages: AsyncStream<WebsocketApi.WebSocket.Message>
  ) async {
    for await message in messages {
      guard !Task.isCancelled else {
        self.close()
        return
      }
      do {
        try await self.handle(message: message)
      } catch {
        self.close()
      }
    }
  }
}

extension WebsocketConnection {
  private func handle(
    message: WebsocketApi.WebSocket.Message
  ) async throws {
    switch message {
    case .text(let string):
      try await self.send(
        response: user.send(
          message: .message(string),
          to: self.room
        )
      )
      break
    case .response(let messages):
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
  
  private func send(response: MessageInfo) {
    self.send(responses: [response])
  }
  
  private func send(responses: [MessageInfo]) {
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
  
  private func send(message: ChatResponse) {
    self.send(messages: [message])
  }
  
  private func send(messages: [ChatResponse]) {
    self.ws.write(messages)
  }
}

extension MessageInfo: PostgresCodable {}

fileprivate extension ChatResponse.Message {
  init(_ message: Backend.Message) {
    self = switch message {
    case .join: .join
    case .message(let string): .message(string)
    case .leave: .leave
    case .disconnect: .disconnect
    }
  }
}

fileprivate extension Backend.Message {
  init(_ message: ChatResponse.Message) {
    self = switch message {
    case .join: .join
    case .message(let string): .message(string)
    case .leave: .leave
    case .disconnect: .disconnect
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
