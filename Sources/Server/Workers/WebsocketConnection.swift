import HummingbirdWSCore
import HummingbirdWebSocket
import HummingbirdFoundation
import Foundation
import Frontend
import Backend
import Persistence
import DistributedCluster
import PostgresNIO

actor WebsocketConnection {

  let room: Room

  private let persistence: Persistence
  private let userInfo: UserInfo
  private let user: User
  private let ws: WebsocketApi.WebSocket
  private var listeningTask: Task<Void, Error>?
  
  init(
    actorSystem: ClusterSystem,
    ws: WebsocketApi.WebSocket,
    persistence: Persistence,
    room: Room,
    userModel: UserModel
  ) async throws {
    self.persistence = persistence
    self.room = room
    let userInfo = UserInfo(
      id: userModel.id,
      name: userModel.name
    )
    self.userInfo = userInfo
    self.ws = ws
    self.user = try await User(
      actorSystem: actorSystem,
      userInfo: userInfo,
      reply: .init { output in
        /// Start listening for messages from other users
        switch output {
        case let .message(message):
          let response = ChatResponse(
            createdAt: message.createdAt,
            user: .init(userInfo),
            message: .init(message.message)
          )
          ws.write([response])
        }
      }
    )
    try await self.start(ws: ws)
  }
  
  func start(ws: WebsocketApi.WebSocket) async throws {
//    await self.sendOldMessages()
    try await self.join()
    self.listeningTask = Task {
      /// Join to the Room and start sending user messages
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
  /// TODO: Move logic to room?
//  private func sendOldMessages() async {
//    let messages = (try? await room.getMessages()) ?? [:]
//    let users = await withTaskGroup(of: UserModel?.self) { group in
//      for message in messages.keys {
//        group.addTask {
//          try? await self.persistence.getUser(id: message.id.rawValue)
//        }
//      }
//      return await group
//        .reduce(into: [UserModel]()) { partialResult, response in
//          guard let response else { return }
//          partialResult.append(response)
//        }
//    }
//    let responses = messages
//      .compactMap { (userInfo, messages) -> ChatResponse? in
//        guard
//          let userModel = users
//            .first(where: { $0.id == userInfo.id.rawValue })
//        else { return .none }
//        return ChatResponse(
//          createdAt: message.createdAt,
//          user: .init(userModel),
//          message: .init(.message(text))
//        )
//      }
//    self.send(messages: responses)
//  }
  
  private func join() async throws {
    try await user.send(message: .join, to: room)
    let message = try await MessageInfo(
      createdAt: .init(),
      roomId: room.getRoomInfo().id,
      userId: self.userInfo.id,
      message: .join
    )
    self.send(
      message: ChatResponse(
        createdAt: message.createdAt,
        user: .init(self.userInfo),
        message: .init(message.message)
      )
    )
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
      try await user.send(
        message: .message(string),
        to: self.room
      )
      try await self.send(
        response: MessageInfo(
          createdAt: Date(),
          roomId: self.room.getRoomInfo().id,
          userId: self.userInfo.id,
          message: .message(string)
        )
      )
      break
    case .response(let messages):
      for message in messages {
        try await user.send(
          message: .init(message),
          to: self.room
        )
        try await self.send(
          response: MessageInfo(
            createdAt: Date(),
            roomId: self.room.getRoomInfo().id,
            userId: self.userInfo.id,
            message: .init(message)
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

fileprivate extension ChatResponse.Message {
  init(_ message: User.Message) {
    self = switch message {
    case .join: .join
    case .message(let string): .message(string)
    case .leave: .leave
    case .disconnect: .disconnect
    }
  }
}

fileprivate extension User.Message {
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
