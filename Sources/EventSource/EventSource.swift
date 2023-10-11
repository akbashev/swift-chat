import Distributed
import DistributedCluster
import FoundationEssentials
import PostgresNIO

/**
 This is a starting point to create some Event Sourcing with actors, thus very rudimentary.
 For now it's all about saving and getting messages (Commands).
 Next steps:
 1. Make Event generic
 2. Add State (with snapshotting on top?)
 
 References:
 1. https://doc.akka.io/docs/akka/current/typed/persistence.html
 2. https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing
 */
protocol Sourceable<Command> {
  associatedtype Command: Codable
  func save(command: Command) async throws
  // TODO: Add predicate (from Foundation?)
  func get(query: String?) async throws -> [Command]
}

distributed public actor EventSource<Command> where Command: Sendable & Codable {
  
  public typealias ActorSystem = ClusterSystem
  
  public enum `Type` {
    case memory
    case postgres(PostgresConnection.Configuration)
  }
  
  public enum Error: Swift.Error {
    case typeNotSupported
  }
    
  private let dataStore: any Sourceable<Command>
  
  distributed public func save(_ command: Command) async throws {
    try await self.dataStore.save(command: command)
  }
  
  // TODO: Maybe add some predicate instead of whole query? (from Foundation?)
  distributed public func get(query: String? = .none) async throws -> [Command] {
    try await self.dataStore.get(query: query)
  }
  
  public init(
    actorSystem: ClusterSystem,
    type: `Type`
  ) async throws where Command: Codable {
    self.actorSystem = actorSystem
    switch type {
    case .memory:
      self.dataStore = Cache()
    case .postgres:
      throw Error.typeNotSupported
    }
    await actorSystem
      .receptionist
      .checkIn(self, with: Self.eventSources)
  }

  public init(
    actorSystem: ClusterSystem,
    type: `Type`
  ) async throws where Command: Codable & PostgresCodable {
    self.actorSystem = actorSystem
    switch type {
    case .memory:
      self.dataStore = Cache()
    case .postgres(let configuration):
      self.dataStore = try await Postgres<Command>(configuration: configuration)
    }
    await actorSystem
      .receptionist
      .checkIn(self, with: Self.eventSources)
  }
}

extension EventSource {
  public static var eventSources: DistributedReception.Key<EventSource<Command>> { "eventSources_\(String(describing: Command.self))" }
}
