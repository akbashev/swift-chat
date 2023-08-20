actor Cache<Command>: Sourceable where Command: Codable {
  
  private struct Data {
    var events: [EventModel<Command>] = []
  }
  
  private var data: Data = .init()
  
  func save(command: Command) {
    self.data.events.append(
      .init(
        id: .init(),
        createdAt: .init(),
        command: command
      )
    )
  }
  
  func get() -> [Command] {
    self.data.events.map { $0.command }
  }
}
