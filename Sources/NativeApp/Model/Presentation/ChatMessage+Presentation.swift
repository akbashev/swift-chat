import Models

extension ChatClient.Message {
  init(
    user: UserPresentation,
    room: RoomPresentation,
    message: Message
  ) {
    let user = UserResponse(user)
    let room = RoomResponse(room)
    let message: ChatMessage.MessagePayload =
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
    message: HeartbeatMessage
  ) {
    let user = UserResponse(user)
    let room = RoomResponse(room)
    self.init(
      user: user,
      room: room,
      message: .HeartbeatMessage(message)
    )
  }
}
