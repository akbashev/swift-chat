import Distributed
import DistributedCluster

public actor ClusterVirtualActorsPlugin {
    
  public enum Error: Swift.Error {
    case factoryError
  }
  
  private var actorSystem: ClusterSystem!
  private var factory: VirtualActorFactory!
  
  private var nodes: [VirtualNode] = []
  
  public func actor<A: VirtualActor>(
    id: VirtualID,
    factory: @escaping (ClusterSystem) async throws -> A
  ) async throws -> A {
    do {
      return try await self.factory.get(id: id)
    } catch {
      switch error {
      case VirtualActorFactory.Error.noActorsAvailable:
        let actor: A = try await factory(self.actorSystem)
        try await self.factory.register(actor: actor, with: id)
        return actor
      default:
        throw error
      }
    }
  }
  
  public init() {}
  
  public func addNode(_ node: VirtualNode) {
    self.nodes.append(node)
  }
}

extension ClusterVirtualActorsPlugin: ActorLifecyclePlugin {
  
  static let pluginKey: Key = "$clusterVirtualActors"
  
  public nonisolated var key: Key {
    Self.pluginKey
  }
  
  public func start(_ system: ClusterSystem) async throws {
    self.actorSystem = system
    self.factory = try await actorSystem.singleton.host(name: "virtual_actor_factory") { actorSystem in
      await VirtualActorFactory(
        actorSystem: actorSystem
      )
    }
  }
  
  public func stop(_ system: ClusterSystem) async {
    self.actorSystem = nil
    self.factory = nil
    self.nodes.removeAll()
  }
  
  nonisolated public func onActorReady<Act: DistributedActor>(_ actor: Act) where Act.ID == ClusterSystem.ActorID {
    // no-op
  }
  
  nonisolated public func onResignID(_ id: ClusterSystem.ActorID) {
    Task { [weak self] in try await self?.factory.close(with: id) }
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
