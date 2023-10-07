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
  
  func get(query: String? = .none) async throws -> [Command] {
    // TODO: Add predicate logic
    let query: String = {
      guard let query else {
        return """
          SELECT command FROM events
        """
      }
      return query
    }()
    let rows = try await connection.query(
      PostgresQuery(stringLiteral: query),
      logger: connection.logger
    )
    var commands: [Command] = []
    for try await (command) in rows.decode((Command).self, context: .default) {
      commands.append(command)
    }
    return commands
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

extension Postgres {
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
      if tablename == "events" {
        return
      }
    }
    
    // create table
    try await self.connection
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
}
