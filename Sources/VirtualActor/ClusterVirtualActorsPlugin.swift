import Distributed
import DistributedCluster

public actor ClusterVirtualActorsPlugin {
    
  public enum Error: Swift.Error {
    case factoryError
    case factoryMissing
  }
  
  private var actorSystem: ClusterSystem!
  private var factory: VirtualActorFactory?
    
  public func actor<A: VirtualActor, D: VirtualActorDependency>(
    id: VirtualID,
    dependency: D
  ) async throws -> A {
    guard let factory else {
      throw Error.factoryMissing
    }
    do {
      return try await factory.get(id: id)
    } catch {
      return switch error {
      case VirtualActorFactory.Error.noActorsAvailable:
        try await factory
          .getNode()
          .spawnActor(
            with: id,
            dependency: dependency
          )
      default:
        throw error
      }
    }
  }
  
  public func actor<A: VirtualActor>(
    id: VirtualID
  ) async throws -> A {
    try await self.actor(
      id: id,
      dependency: None()
    )
  }
  
  public init() {}
}

extension ClusterVirtualActorsPlugin: ActorLifecyclePlugin {
  
  static let pluginKey: Key = "$clusterVirtualActors"
  
  public nonisolated var key: Key {
    Self.pluginKey
  }
  
  public func start(_ system: ClusterSystem) async throws {
    self.actorSystem = system
    self.factory = try await system.singleton.host(name: "virtual_actor_factory") { actorSystem in
      await VirtualActorFactory(
        actorSystem: actorSystem
      )
    }
  }
  
  public func stop(_ system: ClusterSystem) async {
    self.actorSystem = nil
    self.factory = nil
  }
  
  nonisolated public func onActorReady<Act: DistributedActor>(_ actor: Act) where Act.ID == ClusterSystem.ActorID {
    // no-op
  }
  
  nonisolated public func onResignID(_ id: ClusterSystem.ActorID) {
    Task { [weak self] in try await self?.factory?.close(with: id) }
  }
  
}

extension ClusterSystem {
  
  public var virtualActors: ClusterVirtualActorsPlugin {
    let key = ClusterVirtualActorsPlugin.pluginKey
    guard let journalPlugin = self.settings.plugins[key] else {
      fatalError("No plugin found for key: [\(key)], installed plugins: \(self.settings.plugins)")
    }
    return journalPlugin
  }
}
