import Distributed
import DistributedCluster
import Frontend
import Backend
import FoundationEssentials
import Persistence
import EventSource
import Logging
import PostgresNIO
import Hummingbird

@main
public struct Server {
  
  enum Error: Swift.Error, CustomStringConvertible {
    case environmentNotSet
    
    var description: String {
      switch self {
      case .environmentNotSet: "Environment not set"
      }
    }
  }
  
  public static func main() async throws {
    /// 1. Creating nodes
    /// No need for different nodes right now, was just playing a bit.
    /// Idea is then to try manage different nodes and connections for them.
    /// One example I have in mind if room node fails—try to respawn a new one without users loosing a connection.
    let frontendNode = await ClusterSystem("frontend") {
      $0.bindPort = 2550
    }
    let sourceNode = await ClusterSystem("source") {
      $0.bindPort = 2551
    }
    let roomsNode = await ClusterSystem("rooms") {
      $0.bindPort = 2552
    }
    let usersNode = await ClusterSystem("users") {
      $0.bindPort = 2553
    }
    
    
    /// 2. Seeding nodes
    sourceNode.cluster
      .join(endpoint: frontendNode.settings.endpoint)
    roomsNode.cluster
      .join(endpoint: frontendNode.settings.endpoint)
    usersNode.cluster
      .join(endpoint: frontendNode.settings.endpoint)
    
    try await ensureCluster([frontendNode, sourceNode, roomsNode, usersNode], within: .seconds(10))
    
    /// 3. Creating all needed server actors
    
    let logger = Logger(label: "postgres-logger")
    let env = HBEnvironment()

    guard let username = env.get("DB_USERNAME"),
          let password = env.get("DB_PASSWORD"),
          let database = env.get("DB_NAME") else {
      throw Error.environmentNotSet
    }
    
    let config = PostgresConnection.Configuration(
      host: sourceNode.settings.endpoint.host,
      port: 5432,
      username: username,
      password: password,
      database: database,
      tls: .disable
    )

    let connection = try await PostgresConnection.connect(
      configuration: config,
      id: 1,
      logger: logger
    )
    let persistence = try await Persistence(
      actorSystem: sourceNode,
      type: .postgres(connection)
    )
    
    /// Event source could be on different node
    let eventSource = try await EventSource<MessageInfo>(
      actorSystem: sourceNode,
      type: .postgres(connection)
    )
    
    let connectionManager = ConnectionManager(
      roomsNode: roomsNode,
      usersNode: usersNode,
      persistence: persistence,
      eventSource: eventSource
    )
    
    /// 4. Create a frontend actor and wait actorSystem for termination
    try await Frontend(
      actorSystem: frontendNode,
      api: connectionManager.api
    ).actorSystem
      .terminated
  }
  
  /// Waiting for all the clusters to be up
  private static func ensureCluster(_ systems: [ClusterSystem], within: Duration) async throws {
    let nodes = Set(systems.map(\.settings.bindNode))
    
    try await withThrowingTaskGroup(of: Void.self) { group in
      for system in systems {
        group.addTask {
          try await system.cluster.waitFor(nodes, .up, within: within)
        }
      }
      // loop explicitly to propagagte any error that might have been thrown
      for try await _ in group {
        
      }
    }
  }
}

extension MessageInfo: PostgresCodable {}
