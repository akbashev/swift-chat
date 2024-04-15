import Foundation
import DistributedCluster

public class MemoryEventStore: EventStore {
  
  private var dict: [PersistenceID: [Data]] = [:]
  private let encoder: JSONEncoder = JSONEncoder()
  private let decoder: JSONDecoder = JSONDecoder()
  
  public func persistEvent<Event: Codable>(_ event: Event, id: PersistenceID) throws {
    let data = try encoder.encode(event)
    self.dict[id, default: []].append(data)
  }
  
  public func eventsFor<Event: Codable>(id: PersistenceID) throws -> [Event] {
    self.dict[id]?.compactMap(decoder.decode) ?? []
  }
  
  public init(
    dict: [String : [Data]] = [:]
  ) {
    self.dict = dict
  }
}

private extension JSONDecoder {
  func decode<T: Decodable>(_ data: Data) -> T? {
    try? self.decode(T.self, from: data)
  }
}
