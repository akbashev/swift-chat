import Foundation
import PostgresNIO
import NIOCore
import DistributedCluster

public class PostgresEventStore: EventStore {
  
  private let connection: PostgresConnection
  private let encoder: JSONEncoder = .init()
  private let decoder: JSONDecoder = .init()

  public func persistEvent<Event: Codable>(_ event: Event, id: PersistenceID) async throws {
    let data = try encoder.encode(event)
    let nextSequenceNumber = try await self.nextSequenceNumber(for: id)
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    try await connection.query(
      "INSERT INTO events (persistence_id, sequence_number, event) VALUES (\(id), \(nextSequenceNumber), \(buffer))",
      logger: connection.logger
    )
  }
  
  public func eventsFor<Event: Codable>(id: PersistenceID) async throws -> [Event] {
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
  
  init(
    configuration: PostgresConnection.Configuration
  ) async throws {
    let logger = Logger(label: "eventsource-postgres-logger")
    self.connection = try await PostgresConnection.connect(
      configuration: configuration,
      id: 1,
      logger: logger
    )
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
