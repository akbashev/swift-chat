import EventSourcing
import Foundation
import NIOCore
import PostgresNIO

public actor PostgresEventStore: EventStore {

  struct PersistenceTaskId: Hashable, Identifiable, Equatable {
    let buffer: ByteBuffer
    let id: Int
  }

  private let connection: PostgresConnection
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private var persistTasks: [PersistenceTaskId: Task<Void, any Error>] = [:]

  public func persistEvent<Event: Sendable & Codable>(
    _ event: Event,
    id: PersistenceID
  )
    async throws
  {
    let nextSequenceNumber = try await self.nextSequenceNumber(for: id)
    let data = try encoder.encode(event)
    let buffer = ByteBufferAllocator().buffer(data: data)
    let persistenceTaskId = PersistenceTaskId(buffer: buffer, id: nextSequenceNumber)
    guard persistTasks[persistenceTaskId] == .none else {
      return
    }
    self.persistTasks[persistenceTaskId] = Task {
      defer { self.persistTasks.removeValue(forKey: persistenceTaskId) }
      try await connection.query(
        "INSERT INTO events (persistence_id, sequence_number, event) VALUES (\(id), \(nextSequenceNumber), \(buffer))",
        logger: connection.logger
      )
    }
  }

  public func eventsFor<Event: Sendable & Codable>(id: PersistenceID) async throws -> [Event] {
    let rows = try await connection.query(
      "SELECT * FROM events WHERE persistence_id = \(id) ORDER BY sequence_number;",
      logger: connection.logger
    )
    var events: [Data] = []
    for try await buffer in rows.decode((ByteBuffer).self, context: .default) {
      let event = Data(buffer.readableBytesView)
      events.append(event)
    }
    return events.compactMap(decoder.decode)
  }

  private func nextSequenceNumber(for persistenceId: PersistenceID) async throws -> Int {
    let rows = try await connection.query(
      "SELECT MAX(sequence_number) FROM events WHERE persistence_id = \(persistenceId)",
      logger: connection.logger
    )
    for try await (maxSequenceNumber) in rows.decode((Int).self, context: .default) {
      return maxSequenceNumber + 1
    }
    return 0
  }

  public init(
    connection: PostgresConnection,
    encoder: JSONEncoder = .init(),
    decoder: JSONDecoder = .init()
  ) async throws {
    self.connection = connection
    self.encoder = encoder
    self.decoder = decoder
    try await self.setupDatabase()
  }
}

extension PostgresEventStore {
  func setupDatabase() async throws {
    // get list of tables
    let tables = try await self.connection
      .query(
        """
        SELECT tablename FROM pg_catalog.pg_tables
        WHERE schemaname != 'pg_catalog'
        AND schemaname != 'information_schema';
        """,
        logger: self.connection.logger
      )
    // if "events" table exists already return
    for try await (tablename) in tables.decode(String.self, context: .default) {
      if tablename == "journal" {
        return
      }
    }

    // create table
    try await self.connection
      .query(
        """
        CREATE TABLE journal (
            ordering SERIAL,
            "persistence_id" VARCHAR(255) NOT NULL,
            "sequence_number" BIGINT NOT NULL,
            "event" BYTEA NOT NULL,
            PRIMARY KEY(persistence_id, sequence_number)
        );
        """,
        logger: connection.logger
      )
  }
}
