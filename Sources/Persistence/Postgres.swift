import Foundation
import PostgresNIO

actor Postgres: Persistable {

  let connection: PostgresConnection

  func create(input: Persistence.Input) async throws {
    switch input {
    case .participant(let participant):
      try await connection.query(
        "INSERT INTO participants (id, created_at, name) VALUES (\(participant.id), \(participant.createdAt), \(participant.name))",
        logger: connection.logger
      )
    case .room(let room):
      try await connection.query(
        "INSERT INTO rooms (id, created_at, name, description) VALUES (\(room.id), \(room.createdAt), \(room.name), \(room.description))",
        logger: connection.logger
      )
    }
  }

  func update(input: Persistence.Input) async throws {
    switch input {
    case .participant(let participant):
      try await connection.query(
        "UPDATE participants SET \"name\" = \(participant.name) WHERE id = \(participant.id)",
        logger: connection.logger
      )
    case .room(let room):
      try await connection.query(
        "UPDATE rooms SET \"name\" = \(room.name), \"description\" = \(room.description) WHERE id = \(room.id)",
        logger: connection.logger
      )
    }
  }

  func getParticipant(for id: UUID) async throws -> ParticipantModel {
    let rows = try await connection.query(
      "SELECT id, created_at, name FROM participants WHERE id = \(id)",
      logger: connection.logger
    )
    for try await (id, createdAt, name) in rows.decode((UUID, Date, String).self, context: .default) {
      return ParticipantModel(
        id: id,
        createdAt: createdAt,
        name: name
      )
    }
    throw Persistence.Error.participantMissing(id: id)
  }

  func getRoom(for id: UUID) async throws -> RoomModel {
    let rows = try await connection.query(
      "SELECT id, created_at, name, description FROM rooms WHERE id = \(id);",
      logger: connection.logger
    )
    for try await (id, createdAt, name, description) in rows.decode(
      (UUID, Date, String, String?).self,
      context: .default
    ) {
      return RoomModel(
        id: id,
        createdAt: createdAt,
        name: name,
        description: description
      )
    }
    throw Persistence.Error.roomMissing(id: id)
  }

  func searchRoom(query: String) async throws -> [RoomModel] {
    let query = "%" + query + "%"
    let rows = try await connection.query(
      "SELECT id, created_at, name, description FROM rooms WHERE name ILIKE \(query) OR description ILIKE \(query);",
      logger: connection.logger
    )
    var rooms: [RoomModel] = []
    for try await (id, createdAt, name, description) in rows.decode(
      (UUID, Date, String, String?).self,
      context: .default
    ) {
      rooms.append(
        RoomModel(
          id: id,
          createdAt: createdAt,
          name: name,
          description: description
        )
      )
    }
    return rooms
  }

  init(
    configuration: PostgresConnection.Configuration
  ) async throws {
    let logger = Logger(label: "persistence-postgres-logger")
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
    try await self.setupParticipantsTable()
    try await self.setupRoomsTable()
  }

  func setupParticipantsTable() async throws {
    // get list of tables
    let tables =
      try await connection
      .query(
        """
        SELECT tablename FROM pg_catalog.pg_tables
        WHERE schemaname != 'pg_catalog'
        AND schemaname != 'information_schema';
        """,
        logger: connection.logger
      )
    // if "participants" table exists already return
    for try await (tablename) in tables.decode(String.self, context: .default) {
      if tablename == "participants" {
        return
      }
    }

    // create table
    try await connection
      .query(
        """
        CREATE TABLE participants (
            "id" uuid PRIMARY KEY,
            "created_at" date NOT NULL,
            "name" text NOT NULL
        );
        """,
        logger: connection.logger
      )
  }

  func setupRoomsTable() async throws {
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
    // if "rooms" table exists already return
    for try await (tablename) in tables.decode(String.self, context: .default) {
      if tablename == "rooms" {
        return
      }
    }

    // create table
    try await self.connection
      .query(
        """
        CREATE TABLE rooms (
            "id" uuid PRIMARY KEY,
            "created_at" date NOT NULL,
            "name" text NOT NULL,
            "description" text
        );
        """,
        logger: self.connection.logger
      )
  }
}
