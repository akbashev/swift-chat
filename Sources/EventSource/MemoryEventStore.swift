import Foundation
import DistributedCluster

public actor MemoryEventStore: EventStore {
  
  var dict: [PersistenceID: [Data]] = [:]
  let encoder: JSONEncoder = JSONEncoder()
  let decoder: JSONDecoder = JSONDecoder()
  
  public func persistEvent<Event: Encodable>(_ event: Event, id: PersistenceID) throws {
    let data = try encoder.encode(event)
    self.dict[id, default: []].append(data)
  }
  
  public func eventsFor<Event: Decodable>(id: PersistenceID) throws -> [Event] {
    self.dict[id]?.compactMap {
      try? decoder.decode(Event.self, from: $0)
    } ?? []
  }
  
  public init(dict: [String : [Data]] = [:]) {
    self.dict = dict
  }
}
