import Models

extension ChatClient.Message {
  init(
    participant: ParticipantPresentation,
    room: RoomPresentation,
    message: Message
  ) {
    let participant = ParticipantResponse(participant)
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
      participant: participant,
      room: room,
      message: message
    )
  }

  init(
    participant: ParticipantPresentation,
    room: RoomPresentation,
    message: HeartbeatMessage
  ) {
    let participant = ParticipantResponse(participant)
    let room = RoomResponse(room)
    self.init(
      participant: participant,
      room: room,
      message: .HeartbeatMessage(message)
    )
  }
}
