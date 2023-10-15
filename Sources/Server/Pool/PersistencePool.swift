import Distributed
import DistributedCluster
import FoundationEssentials
import PostgresNIO
import Persistence
import Hummingbird
import Logging

/**
 Not actually pool, I guess? Just started to write some custom pool and name sticks now.
 Not sure what is proper name.
 */
distributed actor PersistencePool: LifecycleWatch {
  
  enum Error: Swift.Error, LocalizedError {
    case environmentNotSet
    
    var description: String {
      switch self {
      case .environmentNotSet: "Environment not set"
      }
    }
  }
  
  private lazy var persistences: Set<Persistence> = .init()
  private var listingTask: Task<Void, Never>?
  /// We need reference otherwise PostgresConnection closes.
  private var localPersistence: Persistence?
  
  // TODO: Implement HashRing?
  distributed func get() async throws -> Persistence {
    if let persistence = self.persistences.randomElement() { return persistence }
    if let localPersistence { return localPersistence }
    let persistence = try await PersistencePool.spawnPersistence(clusterSystem: self.actorSystem)
    self.localPersistence = persistence
    return persistence
  }
  
  func terminated(actor id: ActorID) {
    guard let actor = self.persistences.first(where: { $0.id == id }) else { return }
    self.persistences.remove(actor)
  }
  
  private func findPersistances() {
    guard self.listingTask == nil else {
      return actorSystem.log.info("Already looking for persistence actors.")
    }
    
    self.listingTask = Task {
      for await persistence in await actorSystem.receptionist.listing(of: .persistence) {
        self.persistences.insert(persistence)
        self.watchTermination(of: persistence)
      }
    }
  }

  init(
    actorSystem: ClusterSystem
  ) {
    self.actorSystem = actorSystem
    self.findPersistances()
  }
}

extension PersistencePool {
  static func spawnPersistence(
    clusterSystem: ClusterSystem
  ) async throws -> Persistence {
    let logger = Logger(label: "persistence-postgres-logger")
    let env = HBEnvironment()
    
    guard let username = env.get("DB_USERNAME"),
          let password = env.get("DB_PASSWORD"),
          let database = env.get("DB_NAME") else {
      throw Error.environmentNotSet
    }
    
    let config = PostgresConnection.Configuration(
      host: clusterSystem.cluster.node.endpoint.host,
      port: 5432,
      username: username,
      password: password,
      database: database,
      tls: .disable
    )
    
    return try await Persistence(
      actorSystem: clusterSystem,
      type: .postgres(config)
    )
  }
}
