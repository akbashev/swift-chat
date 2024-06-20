import API

extension Components.Schemas.UserResponse {
  init(_ user: UserPresentation) {
    self.init(id: user.id.uuidString, name: user.name)
  }
}

extension Components.Schemas.RoomResponse {
  init(_ room: RoomPresentation) {
    self.init(id: room.id.uuidString, name: room.name, description: room.description)
  }
}
