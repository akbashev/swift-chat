import DistributedCluster
import Store
import Backend
import Models
import Frontend
import FoundationEssentials

actor ConnectionManager {
  
  enum Error: Swift.Error {
    case noConnection
  }
  
  let roomsNode: ClusterSystem
  let usersNode: ClusterSystem
  let roomsManager: RoomsManager
  let store: Store
  
  lazy var api: Api = {
    .init(
      createUser: { [weak self] request in
        guard let self else { throw Error.noConnection }
        let id = request.id.flatMap(UUID.init(uuidString:)) ?? UUID()
        let info = UserInfo(id: id, name: request.name)
        try await self.store.save(.user(info))
        return info.response
      },
      creteRoom: { [weak self] request in
        guard let self else { throw Error.noConnection }
        let id = request.id.flatMap(UUID.init(uuidString:)) ?? UUID()
        let info = RoomInfo(id: id, name: request.name)
        try await self.store.save(.room(info))
        return info.response
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
    _ connection: Api.ChatConnection
  ) async {
    let ws = connection.ws
    do {
      /// 1. Find room
      let room: Room = try await {
        do {
          return try await roomsManager
            .room(for: .init(rawValue: connection.roomId))
        } catch {
          return try await Room(
            actorSystem: roomsNode,
            roomId: .init(rawValue: connection.roomId),
            store: store
          )
        }
      }()
      
      /// 2. Create user for that connection
      let user = try await User(
        actorSystem: usersNode,
        userId: .init(rawValue: connection.userId),
        store: store,
        reply: .init(
          send: { output in
            /// 3. Start listening for messages from other users
            switch output {
              case let .message(message, userInfo, roomInfo):
                switch message {
                  case .message(let message):
                    try await ws.write(
                      .text("\(userInfo.name): \(message)")
                    )
                  case .join:
                    try await ws.write(
                      .text("\(userInfo.name) just connected to the room \(roomInfo.name)")
                    )
                  case .leave:
                    try await ws.write(
                      .text("\(userInfo.name) just left the room \(roomInfo.name)")
                    )
                  case .disconnect:
                    try await ws.write(
                      .text("\(userInfo.name) just disconnected from the room \(roomInfo.name)")
                    )
                }
            }
          }
        )
      )
      
      /// 4. Fetch all current room messages
      let messages = (try? await room.getMessages()) ?? []
      for message in messages {
        switch message.message {
          case .message(let text):
            try await ws.write(
              .text("\(message.user.name): \(text)")
            )
          default:
            break
        }
      }
      
      /// 5. Join to the Room and start sending user messages
      Task {
        try await user.send(message: .join, to: room)
        for await message in ws.readStream() {
          switch message {
            case .text(let string):
              try await user.send(message: .message(string), to: room)
            case .binary(let byteBuffer):
              break
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
    store: Store
  ) {
    self.roomsNode = roomsNode
    self.usersNode = usersNode
    self.roomsManager = RoomsManager(actorSystem: roomsNode)
    self.store = store
    defer {
      Task {
        try await self.roomsManager.findRooms()
      }
    }
  }
}

fileprivate extension UserInfo {
  var response: Api.CreateUserResponse {
    .init(
      id: self.id.rawValue,
      name: self.name
    )
  }
}

fileprivate extension RoomInfo {
  var response: Api.CreateRoomResponse {
    .init(
      id: self.id.rawValue,
      name: self.name
    )
  }
}
