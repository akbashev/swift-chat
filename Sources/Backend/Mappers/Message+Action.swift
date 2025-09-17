extension Room.Message {
  init(_ action: Room.Event.Action) {
    self =
      switch action {
      case .sentMessage(let message, let date):
        .message(message, at: date)
      case .left:
        .leave
      case .disconnected:
        .disconnect
      case .joined:
        .join
      }
  }
}

extension Room.Event.Action {
  init(_ message: Room.Message) {
    self =
      switch message {
      case let .message(message, date):
        .sentMessage(message, at: date)
      case .leave:
        .left
      case .disconnect:
        .disconnected
      case .join:
        .joined
      }
  }
}
