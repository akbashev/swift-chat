extension Room.Message {
  init(_ action: Room.Event.Action) {
    self =
      switch action {
      case .sentMessage(let message, let date):
        .message(message, at: date)
      case .disconnected(let date):
        .disconnect(date)
      case .joined(let date):
        .join(date)
      }
  }
}

extension Room.Event.Action {
  init(_ message: Room.Message) {
    self =
      switch message {
      case let .message(message, date):
        .sentMessage(message, at: date)
      case .disconnect(let date):
        .disconnected(date)
      case .join(let date):
        .joined(date)
      }
  }
}
