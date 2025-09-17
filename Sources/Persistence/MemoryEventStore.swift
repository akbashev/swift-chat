import DistributedCluster
import EventSourcing
import Foundation
import Synchronization

public final class MemoryEventStore: EventStore {

  private let dict: Mutex<[PersistenceID: [Data]]>
  private let encoder: JSONEncoder = JSONEncoder()
  private let decoder: JSONDecoder = JSONDecoder()

  public func persistEvent<Event: Codable & Sendable>(_ event: Event, id: PersistenceID) throws {
    let data = try self.encoder.encode(event)
    self.dict.withLock { $0[id, default: []].append(data) }
  }

  public func eventsFor<Event: Codable & Sendable>(id: PersistenceID) throws -> [Event] {
    self.dict.withLock { $0[id]?.compactMap(decoder.decode) ?? [] }
  }

  public init(
    dict: [String: [Data]] = [:]
  ) {
    self.dict = .init(dict)
  }
}

extension JSONDecoder {
  func decode<T: Decodable>(_ data: Data) -> T? {
    try? self.decode(T.self, from: data)
  }
}
