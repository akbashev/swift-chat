import API

extension ChatClient.Message {
  init(
    user: UserPresentation,
    room: RoomPresentation,
    message: Message
  ) {
    let user = Components.Schemas.UserResponse(user)
    let room = Components.Schemas.RoomResponse(room)
    let message: Components.Schemas.ChatMessage.messagePayload =
      switch message {
      case .disconnect:
        .DisconnectMessage(.init(_type: .disconnect))
      case .join:
        .JoinMessage(.init(_type: .join))
      case .leave:
        .LeaveMessage(.init(_type: .leave))
      case .message(let message, let date):
        .TextMessage(.init(_type: .message, content: message, timestamp: date))
      }
    self.init(
      user: user,
      room: room,
      message: message
    )
  }

  init(
    user: UserPresentation,
    room: RoomPresentation,
    message: Components.Schemas.HeartbeatMessage
  ) {
    let user = Components.Schemas.UserResponse(user)
    let room = Components.Schemas.RoomResponse(room)
    self.init(
      user: user,
      room: room,
      message: .HeartbeatMessage(message)
    )
  }
}
