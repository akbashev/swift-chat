import Foundation

public actor MemoryEventStore: EventStore {
  
  var dict: [String: [Data]] = [:]
  let encoder: JSONEncoder = JSONEncoder()
  let decoder: JSONDecoder = JSONDecoder()

  public func persistEvent<Event: Encodable>(_ event: Event, for id: String) async throws {
    let event = try encoder.encode(event)
    self.dict[id, default: []].append(event)
  }
  
  public func eventsFor<Event: Decodable>(_ persistenceId: String) async throws -> [Event] {
    self.dict[persistenceId]?.compactMap {
      try? decoder.decode(Event.self, from: $0)
    } ?? []
  }
  
  public init(dict: [String : [Data]] = [:]) {
    self.dict = dict
  }
}
