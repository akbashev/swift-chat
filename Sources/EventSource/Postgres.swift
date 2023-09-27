import FoundationEssentials
import PostgresNIO
import Postgres

actor Postgres<Command>: Sourceable where Command: Codable & PostgresCodable {
  
  let connection: PostgresConnection
  
  func save(command: Command) async throws {
    let id = UUID()
    let createdAt = Date()
    try await connection.query(
      "INSERT INTO events (id, created_at, command) VALUES (\(id), \(createdAt), \(command))",
      logger: connection.logger
    )
  }
  
  func get(predicate: String?) async throws -> [Command] {
    // TODO: Add predicate logic
//    let query = [
//     ,
//      predicate
//    ].compactMap { $0 }
//      .joined(separator: " WHERE ")
    let rows = try await connection.query(
      "SELECT command FROM events",
      logger: connection.logger
    )
    var commands: [Command] = []
    for try await (command) in rows.decode((Command).self, context: .default) {
      commands.append(command)
    }
    return commands
  }
  
  static func setupDatabase(for connection: PostgresConnection) async throws {
    // get list of tables
    let tables = try await connection
      .query(
        """
        SELECT tablename FROM pg_catalog.pg_tables
        WHERE schemaname != 'pg_catalog'
        AND schemaname != 'information_schema';
        """,
        logger: connection.logger
      )
    // if "events" table exists already return
    for try await (tablename) in tables.decode(String.self, context: .default) {
      if tablename == "events" {
        return
      }
    }
    
    // create table
    try await connection
      .query(
        """
        CREATE TABLE events (
            "id" uuid PRIMARY KEY,
            "created_at" date NOT NULL,
            "command" jsonb NOT NULL
        );
        """,
        logger: connection.logger
      )
  }
  
  init(
    connection: PostgresConnection
  ) {
    self.connection = connection
  }
}

