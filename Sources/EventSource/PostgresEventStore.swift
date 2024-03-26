//import Foundation
//import PostgresNIO
//import NIOCore
//
//actor PostgresEventStore: EventStore {
//  
//  let connection: PostgresConnection
//  let jsonEncoder: JSONEncoder
//  
//  func persistEvent(_ event: any Encodable, for persistenceId: PersistenceId) async throws {
//    let data = try jsonEncoder.encode(event)
//    let nextSequenceNumber = try await self.nextSequenceNumber(for: persistenceId)
//    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
////    data.writeBytes(event)
//    try await connection.query(
//      "INSERT INTO events (persistence_id, sequence_number, event) VALUES (\(persistenceId), \(nextSequenceNumber), \(buffer))",
//      logger: connection.logger
//    )
//  }
//  
//  func eventsFor(_ persistenceId: PersistenceId) async throws -> [Data] {
//    let rows = try await connection.query(
//      "SELECT * FROM events WHERE persistence_id = \(persistenceId) ORDER BY sequence_number;",
//      logger: connection.logger
//    )
//    var events: [Data] = []
//    for try await buffer in rows.decode((ByteBuffer).self, context: .default) {
//      let event = Data(buffer.readableBytesView)
//      events.append(event)
//    }
//    return events
//  }
//
//  private func nextSequenceNumber(for persistenceId: PersistenceId) async throws -> Int {
//    let rows = try await connection.query(
//      "SELECT MAX(sequence_number) FROM events WHERE persistence_id = \(persistenceId)",
//      logger: connection.logger
//    )
//    for try await (maxSequenceNumber) in rows.decode((Int).self, context: .default) {
//      return maxSequenceNumber + 1
//    }
//    return 0
//  }
//  
//  init(
//    configuration: PostgresConnection.Configuration
//  ) async throws {
//    let logger = Logger(label: "eventsource-postgres-logger")
//    self.connection = try await PostgresConnection.connect(
//      configuration: configuration,
//      id: 1,
//      logger: logger
//    )
//    self.jsonEncoder = JSONEncoder()
//    try await self.setupDatabase()
//  }
//}
//
//extension PostgresEventStore {
//  func setupDatabase() async throws {
//    // get list of tables
//    let tables = try await self.connection
//      .query(
//        """
//        SELECT tablename FROM pg_catalog.pg_tables
//        WHERE schemaname != 'pg_catalog'
//        AND schemaname != 'information_schema';
//        """,
//        logger: self.connection.logger
//      )
//    // if "events" table exists already return
//    for try await (tablename) in tables.decode(String.self, context: .default) {
//      if tablename == "journal" {
//        return
//      }
//    }
//    
//    // create table
//    try await self.connection
//      .query(
//        """
//        CREATE TABLE journal (
//            ordering SERIAL,
//            "persistence_id" VARCHAR(255) NOT NULL,
//            "sequence_number" BIGINT NOT NULL,
//            "event" BYTEA NOT NULL,
//            PRIMARY KEY(persistence_id, sequence_number)
//        );
//        """,
//        logger: connection.logger
//      )
//  }
//}
