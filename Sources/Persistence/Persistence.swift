import Distributed
import DistributedCluster
import FoundationEssentials

protocol Persistable {
  func save(input: Persistence.Input) async
  func getRoom(with id: UUID) async throws -> RoomModel
  func getUser(with id: UUID) async throws -> UserModel
}

distributed public actor Persistence: ClusterSingleton {
  
  public typealias ActorSystem = ClusterSystem
  
  public enum Error: Swift.Error {
    case roomMissing(id: UUID)
    case userMissing(id: UUID)
  }
  
  public enum Input: Sendable, Codable, Equatable {
    case user(UserModel)
    case room(RoomModel)
  }
  
  private let cache: any Persistable
  // TODO: Add database
  // private let database: any Storable
  
  distributed public func save(_ input: Input) async {
    await self.cache.save(input: input)
  }
  
  distributed public func getUser(with id: UUID) async throws -> UserModel {
    try await self.cache.getUser(with: id)
  }
  
  distributed public func getRoom(with id: UUID) async throws -> RoomModel {
    try await self.cache.getRoom(with: id)
  }
  
  public init(
    actorSystem: ClusterSystem
  ) {
    self.actorSystem = actorSystem
    self.cache = Cache()
  }
}
