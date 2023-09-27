import DistributedCluster
import Backend
import Frontend
import FoundationEssentials
import NIOCore
import EventSource
import Persistence

actor ConnectionManager {
  
  enum Error: Swift.Error {
    case noConnection
  }
  
  let roomsNode: ClusterSystem
  let usersNode: ClusterSystem
  let roomsManager: RoomsManager
  let persistence: Persistence
  let eventSource: EventSource<MessageInfo>

  lazy var api: Api = {
    .init(
      createUser: { [weak self] request in
        guard let self else { throw Error.noConnection }
        let name = request.name
        let id = UUID()
        try await self.persistence.create(
          .user(
            .init(
              id: id,
              createdAt: .init(),
              name: request.name
            )
          )
        )
        return UserResponse(
          id: id,
          name: name
        )
      },
      creteRoom: { [weak self] request in
        guard let self else { throw Error.noConnection }
        let id = UUID()
        let name = request.name
        let description = request.description
        try await self.persistence.create(
          .room(
            .init(
              id: id,
              createdAt: .init(),
              name: request.name,
              description: request.description
            )
          )
        )
        return RoomResponse(
          id: id,
          name: name,
          description: description
        )
      },
      searchRoom: { [weak self] request in
        guard let self else { throw Error.noConnection }
        let query = request.query
        let rooms = try await self.persistence.searchRoom(query: query)
        return rooms.map {
          RoomResponse(
            id: $0.id,
            name: $0.name,
            description: $0.description
          )
        }
      },
      chat: { chatConnection in
        Task { [weak self] in
          guard let self else { throw Error.noConnection }
          for await connection in chatConnection {
            await self.handle(connection)
          }
        }
      }
    )
  }()
  
  func handle(
    _ connection: ChatConnection
  ) async {
    let ws = connection.ws
    do {
      /// 1. Find room
      let roomModel = try await persistence.getRoom(id: connection.roomId)
      let roomInfo = RoomInfo(
        id: roomModel.id,
        name: roomModel.name,
        description: roomModel.description
      )
      let room: Room = try await {
        do {
          return try await roomsManager
            .room(for: .init(rawValue: connection.roomId))
        } catch {
          return try await Room(
            actorSystem: roomsNode,
            roomInfo: roomInfo,
            eventSource: eventSource
          )
        }
      }()
    
      /// 2. Create user for that connection
      let userModel = try await persistence.getUser(id: connection.userId)
      let userInfo = UserInfo(
        id: userModel.id,
        name: userModel.name
      )
      let user = try await User(
        actorSystem: usersNode,
        userInfo: userInfo,
        reply: .init(
          send: { output in
            /// 3. Start listening for messages from other users
            switch output {
              case let .message(message, userInfo, _):
                var data = ByteBuffer()
                _ = try? data.writeJSONEncodable(
                  [
                    ChatResponse(
                      createdAt: message.createdAt,
                      user: .init(userInfo),
                      message: .init(message.message)
                    )
                  ]
                )
                try await ws.write(.binary(data))
            }
          }
        )
      )
      
      /// 4. Listen for disconnection
      ws.onClose { _ in
        Task {
          try? await user.send(message: .disconnect, to: room)
        }
      }
      
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
            guard let userModel = users.first(where: { $0.id == message.userId.rawValue }) else { return .none }
            return ChatResponse(
              createdAt: message.createdAt,
              user: .init(userModel),
              message: .init(.message(text))
            )
          default:
            return .none
        }
      }
      
      var data = ByteBuffer()
      _ = try? data.writeJSONEncodable(
        responses
      )
      try? await ws.write(.binary(data))
      
      /// 6. Join to the Room and start sending user messages
      Task {
        let messageInfo = try await user.send(message: .join, to: room)
        var data = ByteBuffer()
        _ = try? data.writeJSONEncodable(
          [
            ChatResponse(
              createdAt: messageInfo.createdAt,
              user: .init(userInfo),
              message: .init(messageInfo.message)
            )
          ]
        )
        try await ws.write(.binary(data))
        for await message in ws.readStream() {
          switch message {
            case .text(let string):
              try? await user.send(message: .message(string), to: room)
            case .binary(var data):
              do {
                guard let messages = try data.readJSONDecodable([Message].self, length: data.readableBytes) else { return }
                for message in messages {
                  let messageInfo = try await user.send(message: message, to: room)
                  var data = ByteBuffer()
                  _ = try? data.writeJSONEncodable(
                    [
                      ChatResponse(
                        createdAt: messageInfo.createdAt,
                        user: .init(userInfo),
                        message: .init(messageInfo.message)
                      )
                    ]
                  )
                  try await ws.write(.binary(data))
                }
              } catch {
                usersNode.log.error("\(error)")
              }
          }
        }
      }
    } catch {
      try? await ws.close(code: .unacceptableData)
    }
  }
  
  init(
    roomsNode: ClusterSystem,
    usersNode: ClusterSystem,
    persistence: Persistence,
    eventSource: EventSource<MessageInfo>
  ) {
    self.roomsNode = roomsNode
    self.usersNode = usersNode
    self.roomsManager = RoomsManager(actorSystem: roomsNode)
    self.persistence = persistence
    self.eventSource = eventSource
    defer {
      Task {
        try await self.roomsManager.findRooms()
      }
    }
  }
}

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
