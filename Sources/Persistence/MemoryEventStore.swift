import DistributedCluster
import EventSourcing
import Foundation
import Synchronization

public final class MemoryEventStore: EventStore {

  private let dict: Mutex<[PersistenceID: [Int64: Data]]>
  private let encoder: JSONEncoder = JSONEncoder()
  private let decoder: JSONDecoder = JSONDecoder()

  public func persistEvent<Event: Codable & Sendable>(
    _ event: Event,
    id: PersistenceID,
    sequenceNumber: Int64
  ) throws {
    let data = try self.encoder.encode(event)
    self.dict.withLock { dict in
      /// First write wins—retries of an already-stored sequence number are a no-op.
      guard dict[id]?[sequenceNumber] == nil else { return }
      dict[id, default: [:]][sequenceNumber] = data
    }
  }

  public func eventsFor<Event: Codable & Sendable>(
    id: PersistenceID,
    fromSequenceNumber: Int64
  ) throws -> [Event] {
    self.dict.withLock { dict in
      (dict[id] ?? [:])
        .filter { $0.key >= fromSequenceNumber }
        .sorted { $0.key < $1.key }
        .compactMap { self.decoder.decode($0.value) }
    }
  }

  public init(
    dict: [PersistenceID: [Int64: Data]] = [:]
  ) {
    self.dict = .init(dict)
  }
}

extension JSONDecoder {
  func decode<T: Decodable>(_ data: Data) -> T? {
    try? self.decode(T.self, from: data)
  }
}
