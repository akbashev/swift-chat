import Foundation
import DistributedCluster

distributed public actor MemoryEventStore: EventStore {
  
  private var dict: [PersistenceID: [Data]] = [:]
  private let encoder: JSONEncoder = JSONEncoder()
  private let decoder: JSONDecoder = JSONDecoder()
  
  distributed public func persistEvent<Event: Codable>(_ event: Event, id: PersistenceID) throws {
    let data = try encoder.encode(event)
    self.dict[id, default: []].append(data)
  }
  
  distributed public func eventsFor<Event: Codable>(id: PersistenceID) throws -> [Event] {
    self.dict[id]?.compactMap(decoder.decode) ?? []
  }
  
  public init(
    actorSystem: ActorSystem,
    dict: [String : [Data]] = [:]
  ) {
    self.actorSystem = actorSystem
    self.dict = dict
  }
}

private extension JSONDecoder {
  func decode<T: Decodable>(_ data: Data) -> T? {
    try? self.decode(T.self, from: data)
  }
}
