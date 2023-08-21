import Distributed
import DistributedCluster
import FoundationEssentials

protocol Persistable {
  func save(input: Persistence.Input) async
  func getRoom(id: UUID) async throws -> RoomModel
  func getRoom(name: String) async throws -> RoomModel
  func getUser(id: UUID) async throws -> UserModel
}

distributed public actor Persistence: ClusterSingleton {
  
  public typealias ActorSystem = ClusterSystem
  
  public enum Error: Swift.Error {
    case roomMissing(id: UUID)
    case roomMissing(name: String)
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
  
  distributed public func getUser(id: UUID) async throws -> UserModel {
    try await self.cache.getUser(id: id)
  }
  
  distributed public func getRoom(id: UUID) async throws -> RoomModel {
    try await self.cache.getRoom(id: id)
  }
  
  distributed public func getRoom(name: String) async throws -> RoomModel {
    try await self.cache.getRoom(name: name)
  }
  
  public init(
    actorSystem: ClusterSystem
  ) {
    self.actorSystem = actorSystem
    self.cache = Cache()
  }
}
