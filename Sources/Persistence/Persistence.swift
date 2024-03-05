import Distributed
import DistributedCluster
import Foundation
import PostgresNIO

/**
 This is a starting point to create some persistence with actors, thus very rudimentary.
 It's working for now, but there is not consistency handling acros multiple nodes.
 For now not sure yet about next steps to be taken...
 
 References:
 1. https://doc.akka.io/docs/akka/current/typed/distributed-data.html
 2. https://www.erlang.org/doc/man/mnesia.html
 3. https://www.cs.cornell.edu/andru/papers/mixt
 */
protocol Persistable {
  func create(input: Persistence.Input) async throws
  func update(input: Persistence.Input) async throws
  
  func getRoom(id: UUID) async throws -> RoomModel
  func searchRoom(query: String) async throws -> [RoomModel]
  
  func getUser(id: UUID) async throws -> UserModel
}

distributed public actor Persistence {
  
  public typealias ActorSystem = ClusterSystem
  
  public enum `Type`: Sendable {
    case memory
    case postgres(PostgresConnection.Configuration)
  }
  
  public enum Error: Swift.Error {
    case roomMissing(id: UUID)
    case roomMissing(name: String)
    case userMissing(id: UUID)
  }
  
  public enum Input: Sendable, Codable, Equatable {
    case user(UserModel)
    case room(RoomModel)
  }
  
  private let persistance: any Persistable
  
  distributed public func create(_ input: Input) async throws {
    try await self.persistance.create(input: input)
  }
  
  distributed public func update(_ input: Input) async throws {
    try await self.persistance.update(input: input)
  }
  
  distributed public func getUser(id: UUID) async throws -> UserModel {
    try await self.persistance.getUser(id: id)
  }
  
  distributed public func getRoom(id: UUID) async throws -> RoomModel {
    try await self.persistance.getRoom(id: id)
  }
  
  distributed public func searchRoom(query: String) async throws -> [RoomModel] {
    try await self.persistance.searchRoom(query: query)
  }
  
  public init(
    actorSystem: ClusterSystem,
    type: `Type`
  ) async throws {
    self.actorSystem = actorSystem
    switch type {
    case .memory:
      self.persistance = Cache()
    case .postgres(let configuration):
      self.persistance = try await Postgres(
        configuration: configuration
      )
    }
    await actorSystem
      .receptionist
      .checkIn(self, with: .persistence)
  }
}

extension DistributedReception.Key {
  public static var persistence: DistributedReception.Key<Persistence> { "persistences" }
}

extension PostgresConnection.Configuration: @unchecked Sendable {}
