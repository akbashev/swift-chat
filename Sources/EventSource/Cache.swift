actor Cache<Command>: Sourceable where Command: Codable & Sendable {
  
  private struct Data {
    var events: [EventModel<Command>] = []
  }
  
  private var data: Data = .init()
  
  func save(command: Command) throws {
    self.data.events.append(
      .init(
        id: .init(),
        createdAt: .init(),
        command: command
      )
    )
  }
  
  func get(query: String? = .none) -> [Command] {
    self.data.events.map { $0.command }
  }
}
