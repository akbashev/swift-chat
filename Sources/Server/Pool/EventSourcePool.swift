import Distributed
import DistributedCluster
import FoundationEssentials
import PostgresNIO
import EventSource
import Hummingbird
import Logging
import Backend

distributed actor EventSourcePool: LifecycleWatch {

  public enum Error: Swift.Error, LocalizedError {
    case environmentNotSet
    
    var description: String {
      switch self {
      case .environmentNotSet: "Environment not set"
      }
    }
  }
  
  private lazy var eventSources: Set<EventSource<MessageInfo>> = .init()
  private var listingTask: Task<Void, Never>?
  /// We need reference otherwise PostgresConnection closes.
  private var localEventSource: EventSource<MessageInfo>?
  
  // TODO: Implement HashRing?
  distributed func get() async throws -> EventSource<MessageInfo> {
    if let eventSource = self.eventSources.randomElement() {
      self.localEventSource = .none
      return eventSource
    }
    if let localEventSource { return localEventSource }
    let eventSource = try await Self.spawnEventSource(clusterSystem: self.actorSystem)
    self.localEventSource = eventSource
    return eventSource
  }
  
  func terminated(actor id: ActorID) {
    guard let actor = self.eventSources.first(where: { $0.id == id }) else { return }
    self.eventSources.remove(actor)
  }
  
  private func findEventSources() {
    guard self.listingTask == nil else {
      return self.actorSystem.log.info("Already looking for event source actors.")
    }
    
    self.listingTask = Task {
      for await eventSource in await self.actorSystem.receptionist.listing(of: EventSource<MessageInfo>.eventSources) {
        self.eventSources.insert(eventSource)
      }
    }
  }
  
  static func spawnEventSource(
    clusterSystem: ClusterSystem
  ) async throws -> EventSource<MessageInfo> {
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
    
    return try await EventSource<MessageInfo>.init(
      actorSystem: clusterSystem,
      type: .postgres(config)
    )
  }
  
  init(
    actorSystem: ClusterSystem
  ) {
    self.actorSystem = actorSystem
    self.findEventSources()
  }
}
