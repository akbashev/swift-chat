import FoundationEssentials

actor Cache: Persistable {
  
  private struct Data: Equatable {
    var users: Set<UserModel> = []
    var rooms: Set<RoomModel> = []
  }
  
  private var data: Data = .init()
  
  func save(input: Persistence.Input) {
    switch input {
      case .user(let user):
        self.data.users
          .insert(user)
      case .room(let room):
        self.data.rooms
          .insert(room)
    }
  }
  
  func getUser(id: UUID) throws -> UserModel {
    guard let userInfo = data.users.first(where: { $0.id == id }) else {
      throw Persistence.Error.userMissing(id: id)
    }
    return userInfo
  }
  
  func getRoom(id: UUID) throws -> RoomModel {
    guard let roomInfo = data.rooms.first(where: { $0.id == id }) else {
      throw Persistence.Error.roomMissing(id: id)
    }
    return roomInfo
  }
  
  func getRoom(name: String) throws -> RoomModel {
    guard let roomInfo = data.rooms.first(where: { $0.name == name }) else {
      throw Persistence.Error.roomMissing(name: name)
    }
    return roomInfo
  }
}

extension UserModel: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.id.uuidString)
  }
}

extension RoomModel: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.id.uuidString)
  }
}
