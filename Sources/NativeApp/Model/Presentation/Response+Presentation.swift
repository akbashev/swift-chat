import Models

extension UserResponse {
  init(_ user: UserPresentation) {
    self.init(id: user.id.uuidString, name: user.name)
  }
}

extension RoomResponse {
  init(_ room: RoomPresentation) {
    self.init(id: room.id.uuidString, name: room.name, description: room.description)
  }
}
