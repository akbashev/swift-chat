import Distributed
import DistributedCluster
import Models

// TODO: Create seperate models for Store
protocol Storable {
  func save(input: Store.Input) async
  func getMessages(for roomId: RoomInfo.ID) async -> [MessageInfo]
  func getRoom(with id: RoomInfo.ID) async throws -> RoomInfo
  func getUser(with id: UserInfo.ID) async throws -> UserInfo
}

distributed public actor Store: ClusterSingleton {
  
  public typealias ActorSystem = ClusterSystem
  
  public enum `Type` {
    case memory
    case database
  }
  
  public enum Error: Swift.Error {
    case roomMissing(id: RoomInfo.ID)
    case userMissing(id: UserInfo.ID)
    case typeNotSupported
  }
  
  public enum Input: Sendable, Codable, Equatable {
    case message(MessageInfo)
    case user(UserInfo)
    case room(RoomInfo)
  }
  
  private let dataStore: any Storable
  
  distributed public func save(_ input: Input) async {
    await self.dataStore.save(input: input)
  }
  
  distributed public func getMessages(for roomId: RoomInfo.ID) async -> [MessageInfo] {
    await self.dataStore.getMessages(for: roomId)
  }
  
  distributed public func getUser(with id: UserInfo.ID) async throws -> UserInfo {
    try await self.dataStore.getUser(with: id)
  }
  
  distributed public func getRoom(with id: RoomInfo.ID) async throws -> RoomInfo {
    try await self.dataStore.getRoom(with: id)
  }
  
  public init(
    actorSystem: ClusterSystem,
    type: `Type`
  ) throws {
    self.actorSystem = actorSystem
    switch type {
      case .memory:
        self.dataStore = MemoryCache()
      case .database:
        throw Error.typeNotSupported
    }
  }
}
