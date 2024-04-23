import Distributed
import DistributedCluster

typealias DefaultDistributedActorSystem = ClusterSystem

distributed public actor VirtualActorFactory: LifecycleWatch, ClusterSingleton {
  public enum Error: Swift.Error {
    case noNodesAvailable
  }
  
  private lazy var virtualNodes: Set<VirtualNode> = .init()
  private var listeningTask: Task<Void, Never>?

  public func terminated(actor id: ActorID) async {
    guard let virtualNode = self.virtualNodes.first(where: { $0.id == id }) else { return }
    self.virtualNodes.remove(virtualNode)
  }
  
  private func findVirtualNodes() {
    guard self.listeningTask == nil else {
      actorSystem.log.info("Already looking for nodes")
      return
    }
    
    self.listeningTask = Task {
      for await virtualNode in await actorSystem.receptionist.listing(of: VirtualNode.key) {
        self.virtualNodes.insert(virtualNode)
        self.watchTermination(of: virtualNode)
      }
    }
  }
  
  /// - Parameters:
  /// - id—external (not system) id of an actor.
  /// - dependency—only needed when spawning an actor.
  distributed public func get<A: VirtualActor>(id: VirtualID) async throws -> A {
    for virtualNode in virtualNodes {
      if let actor: A = try? await virtualNode.find(id: id) {
        return actor
      }
    }
    throw Error.noNodesAvailable
  }
  
  distributed public func register<A: VirtualActor>(actor: A) async throws {
    guard let node = virtualNodes.randomElement() else {
      // There should be always a node (at least local node), if not—something sus
      throw Error.noNodesAvailable
    }
    try await node.register(actor: actor)
  }
  
  /// Actors should be cleaned automatically, but for now unfortunately manual cleaning.
  distributed public func closeActor(for id: VirtualID) async {
    for node in virtualNodes {
      try? await node.close(with: id)
    }
  }

  /// - Parameters:
  ///  - spawn—definining how an actor should be created.
  ///  Local node is created while initialising a factory.
  public init(
    actorSystem: ClusterSystem
  ) async {
    self.actorSystem = actorSystem
    self.findVirtualNodes()
  }
}

distributed public actor VirtualNode {
  
  public enum Error: Swift.Error {
    case noActorAvailable
  }
  
  private lazy var virtualActors: [VirtualID: any VirtualActor] = [:]
  
  distributed fileprivate func register<A: VirtualActor>(actor: A) {
    guard let id = actor.metadata.virtualID else { return }
    self.virtualActors[id] = actor
  }
  
  distributed public func find<A: VirtualActor>(id: VirtualID) async throws -> A {
    guard let actor = self.virtualActors[id] as? A else {
      throw Error.noActorAvailable
    }
    return actor
  }
  
  distributed public func close(
    with id: VirtualID
  ) async {
    self.virtualActors.removeValue(forKey: id)
  }
  
  public init(
    actorSystem: ClusterSystem
  ) async {
    self.actorSystem = actorSystem
    await actorSystem
      .receptionist
      .checkIn(self, with: Self.key)
  }
}

extension VirtualNode {
  static var key: DistributedReception.Key<VirtualNode> { "virtual_nodes" }
}

public typealias VirtualID = String

public protocol VirtualActor: DistributedActor, Codable where ActorSystem == ClusterSystem {
  static var virtualFactoryKey: String { get }
}

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
      case VirtualActorFactory.Error.noNodesAvailable:
        let actor: A = try await factory(actorSystem)
        try await self.factory.register(actor: actor)
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

extension ClusterVirtualActorsPlugin: Plugin {
  
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

extension ActorMetadataKeys {
  public var virtualID: ActorMetadataKey<VirtualID> { "$vitrualID" }
}
