import Models

actor MemoryCache: Storable {
  
  private struct Data: Equatable {
    var messages: [MessageInfo] = []
    var users: Set<UserInfo> = []
    var rooms: Set<RoomInfo> = []
  }
  
  private var data: Data = .init()
  
  func save(input: Store.Input) {
    switch input {
      case .message(let message):
        self.data.messages
          .append(message)
      case .user(let user):
        self.data.users
          .insert(user)
      case .room(let room):
        self.data.rooms
          .insert(room)
    }
  }
  
  func getMessages(for roomId: RoomInfo.ID) -> [MessageInfo] {
    self.data
      .messages
      .filter { $0.room.id == roomId }
  }
  
  func getUser(with id: UserInfo.ID) throws -> UserInfo {
    guard let userInfo = data.users.first(where: { $0.id == id }) else {
      throw Store.Error.userMissing(id: id)
    }
    return userInfo
  }
  
  func getRoom(with id: RoomInfo.ID) throws -> RoomInfo {
    guard let roomInfo = data.rooms.first(where: { $0.id == id }) else {
      throw Store.Error.roomMissing(id: id)
    }
    return roomInfo
  }
}

extension UserInfo: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.id.rawValue)
  }
}

extension RoomInfo: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.id.rawValue)
  }
}
