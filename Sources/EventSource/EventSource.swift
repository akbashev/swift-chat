import Distributed
import DistributedCluster
import FoundationEssentials
import PostgresNIO

// TODO: Create seperate models for Store
protocol Sourceable<Command> {
  associatedtype Command: Codable
  func save(command: Command) async throws
  // TODO: Add predicate (from Foundation?)
  func get(query: String?) async throws -> [Command]
}

distributed public actor EventSource<Command>: ClusterSingleton where Command: Sendable & Codable {
  
  public typealias ActorSystem = ClusterSystem
  
  public enum `Type` {
    case memory
    case postgres(PostgresConnection)
  }
  
  public enum Error: Swift.Error {
    case typeNotSupported
  }
  
  private let dataStore: any Sourceable<Command>
  
  distributed public func save(_ command: Command) async throws {
    try await self.dataStore.save(command: command)
  }
  
  // TODO: Add predicate (from Foundation?)
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
  }

  public init(
    actorSystem: ClusterSystem,
    type: `Type`
  ) async throws where Command: Codable & PostgresCodable {
    self.actorSystem = actorSystem
    switch type {
    case .memory:
      self.dataStore = Cache()
    case .postgres(let connection):
      try await Postgres<Command>.setupDatabase(for: connection)
      self.dataStore = Postgres<Command>(connection: connection)
    }
  }
}
