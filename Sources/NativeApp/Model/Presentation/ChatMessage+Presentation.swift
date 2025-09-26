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
      case .disconnect(let date):
        .DisconnectMessage(.init(disconnectedAt: date))
      case .join(let date):
        .JoinMessage(.init(joinedAt: date))
      case .message(let message, let date):
        .TextMessage(.init(content: message, timestamp: date))
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
