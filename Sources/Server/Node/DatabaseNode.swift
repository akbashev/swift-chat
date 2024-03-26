import DistributedCluster
import Persistence
import EventSource
import Backend
import Hummingbird
import PostgresNIO

/// Is it a pool? Should I call Node? Not sure...
distributed actor DatabaseNode {
  
  enum Error: Swift.Error {
    case environmentNotSet
  }
    
  let eventSource: EventSource<Room.State, MessageInfo, Event>
  let persistence: Persistence
  
  init(
    actorSystem: ClusterSystem
  ) async throws {
    self.actorSystem = actorSystem
    let config = try Self.postgresConfig(
      host: actorSystem.cluster.node.endpoint.host
    )
//    self.eventSource = try await EventSource<Room.State, MessageInfo, Event>(
//      actorSystem: actorSystem,
//      type: .postgres(config)
//    )
    self.persistence = try await Persistence(
      actorSystem: actorSystem,
      type: .postgres(config)
    )
    await actorSystem
      .receptionist
      .checkIn(self, with: .databaseNodes)
  }
  
//  distributed func getPersistence() -> Persistence {
//    return self.persistence
//  }
//  
//  distributed func getEventSource() -> EventSource<Room.State, MessageInfo, Event> {
//    return self.eventSource
//  }
}

extension DistributedReception.Key {
  static var databaseNodes: DistributedReception.Key<DatabaseNode> { "database_nodes" }
}

extension DatabaseNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {
    let dbNode = await ClusterSystem("database") {
      $0.bindHost = host
      $0.bindPort = port
    }
    
    dbNode.cluster.join(host: "127.0.0.1", port: 2550)
    try await Self.ensureCluster(dbNode, within: .seconds(10))
    let databaseNode = try await Self(actorSystem: dbNode)
    try await dbNode.terminated
  }
}

extension DatabaseNode {
  private static func postgresConfig(
    host: String
  ) throws -> PostgresConnection.Configuration {
    let env = HBEnvironment()
    guard let username = env.get("DB_USERNAME"),
          let password = env.get("DB_PASSWORD"),
          let database = env.get("DB_NAME") else {
      throw DatabaseNode.Error.environmentNotSet
    }
    
    return PostgresConnection.Configuration(
      host: host,
      port: 5432,
      username: username,
      password: password,
      database: database,
      tls: .disable
    )
  }
}

extension Event: PostgresCodable {}
