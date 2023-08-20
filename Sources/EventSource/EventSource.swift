import Distributed
import DistributedCluster
import FoundationEssentials

// TODO: Create seperate models for Store
protocol Sourceable<Command> {
  associatedtype Command: Codable
  func save(command: Command) async
  // TODO: Add predicate (from Foundation?)
  func get() async -> [Command]
}

distributed public actor EventSource<Command>: ClusterSingleton where Command: Sendable & Codable {
  
  public typealias ActorSystem = ClusterSystem
  
  public enum `Type` {
    case memory
    case database
  }
  
  public enum Error: Swift.Error {
    case typeNotSupported
  }
  
  private let dataStore: any Sourceable<Command>
  
  distributed public func save(_ command: Command) async {
    await self.dataStore.save(command: command)
  }
  
  // TODO: Add predicate (from Foundation?)
  distributed public func get() async -> [Command] {
    await self.dataStore.get()
  }

  public init(
    actorSystem: ClusterSystem,
    type: `Type`
  ) throws {
    self.actorSystem = actorSystem
    switch type {
      case .memory:
        self.dataStore = Cache()
      case .database:
        throw Error.typeNotSupported
    }
  }
}
