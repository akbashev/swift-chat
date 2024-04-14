import Distributed
import DistributedCluster

typealias DefaultDistributedActorSystem = ClusterSystem

distributed public actor VirtualActorFactory<Actor>: LifecycleWatch, ClusterSingleton
  where Actor: VirtualActor {
    
  public enum Error: Swift.Error {
    case noNodesAvailable
  }
  
  private lazy var virtualNodes: Set<VirtualNode<Actor>> = .init()
  private var listeningTask: Task<Void, Never>?
  // How actors are spawned should be defined by VirtualActorFactory owner atm
  private let spawn: () async throws -> Actor

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
      for await virtualNode in await actorSystem.receptionist.listing(of: VirtualNode<Actor>.key) {
        self.virtualNodes.insert(virtualNode)
        self.watchTermination(of: virtualNode)
      }
    }
  }
  
  /// - Parameters:
  /// - id—external (not system) id of an actor.
  /// - dependency—only needed when spawning an actor.
  distributed public func get(id: VirtualID) async throws -> Actor {
    for virtualNode in virtualNodes {
      if let actor = try? await virtualNode.find(id: id) {
        return actor
      }
    }
    guard let node = virtualNodes.randomElement() else {
      // There should be always a node (at least local node), if not—something sus
      throw Error.noNodesAvailable
    }
    let actor = try await self.spawn()
    try await node.register(actor: actor, with: id)
    return actor
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
    actorSystem: ClusterSystem,
    spawn: @escaping @Sendable () async throws -> Actor
  ) async {
    self.actorSystem = actorSystem
    self.spawn = spawn
    self.findVirtualNodes()
  }
}

distributed public actor VirtualNode<Actor> where Actor: VirtualActor {
  
  public enum Error: Swift.Error {
    case noActorAvailable
  }
  
  private lazy var virtualActors: [VirtualID: Actor] = [:]
  
  distributed fileprivate func register(actor: Actor, with id: VirtualID) {
    self.virtualActors[id] = actor
  }
  
  distributed public func find(id: VirtualID) async throws -> Actor {
    guard let room = self.virtualActors[id] else {
      throw Error.noActorAvailable
    }
    return room
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
  static var key: DistributedReception.Key<VirtualNode<Actor>> { "virtual_group_\(Self.self)" }
}

public typealias VirtualID = String

public protocol VirtualActor: DistributedActor, Codable where ActorSystem == ClusterSystem {
  static var key: String { get }
  
  distributed var virtualId: VirtualID { get }
}

extension VirtualActor {
  public static func virtual(
    actorSystem: ClusterSystem,
    id: VirtualID,
    factory: @escaping (ClusterSystem) async throws -> Self
  ) async throws -> Self {
    try await actorSystem
      .virtualActors
      .get(
        id: id,
        factory: factory
      )
  }
}

public actor ClusterVirtualActorsPlugin {
    
  public enum Error: Swift.Error {
    case factoryError
  }
  
  private var actorSystem: ClusterSystem!
  public func get<A: VirtualActor>(
    id: VirtualID,
    factory: @escaping (ClusterSystem) async throws -> A
  ) async throws -> A {
    try await actorSystem.singleton.host(name: A.key) { actorSystem in
      await VirtualActorFactory<A>(
        actorSystem: actorSystem,
        spawn: {
          try await factory(actorSystem)
        }
      )
    }
    .get(id: id)
  }
  
  public init() {}
}

extension ClusterVirtualActorsPlugin: _Plugin {
  static let pluginKey: Key = "$clusterVirtualActors"
  
  public nonisolated var key: Key {
    Self.pluginKey
  }
  
  public func start(_ system: ClusterSystem) async throws {
    self.actorSystem = system
  }
  
  public func stop(_ system: ClusterSystem) async {
    self.actorSystem = nil
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
  
  public func add<V: VirtualActor>(_ type: V.Type) async throws -> VirtualNode<V> {
    await VirtualNode<V>(actorSystem: self)
  }
}
