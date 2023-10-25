import Distributed
import DistributedCluster

typealias DefaultDistributedActorSystem = ClusterSystem

/// Naive implementation of Virtual Actors
/// 
/// **Don't overuse it**: this pattern should be used on purpose, e.g. when you have number of dynamic *transparent* actors with some id.
/// If you have limited, already defined set of actors—just create and reference them in a seperate node.
///
/// - **VirtualActor**—any distributed actor to work with,
/// - **ID**—external id of this actor (**NOT ClusterSystem.ActorID**),
/// - **Dependency**—some external dependencies (struct or distributed actor) to initialise an actor.
///
///
/// ```swift
/// // Some hypothetical Node 1
/// let exampleNode1 = VirtualNode<Example, String>(actorSystem: node1)
/// // Some hypothetical Node 2
/// let exampleNode2 = VirtualNode<Example, String>(actorSystem: node2)
/// // Main node
/// let factory = VirtualActorFactory<Example, String, SomeDependency>(actorSystem: main) { actorSystem, id, dependencies in
///    return Example(actorSystem: actorSystem, dependencies)
/// }
/// // This actor is created when referenced and location transparent.
/// let actor = try await factory.get(id: "first_example", dependency: SomeDependency())
/// ```
/// 
/// - TODO:
/// - Add consistent hashing
/// - Automatic actor cleaning
/// - Improve spawning and dependency handling? 🤔
distributed public actor VirtualActorFactory<VirtualActor, ID, Dependency>: LifecycleWatch
  where VirtualActor: DistributedActor & Codable,
        ID: Hashable & Codable,
        Dependency: Codable {
  
  public enum Error: Swift.Error {
    case noNodesAvailable
  }
  
  private lazy var virtualNodes: Set<VirtualNode<VirtualActor, ID>> = .init()
  private var listeningTask: Task<Void, Never>?
  // How actors are spawned should be defined by VirtualActorFactory owner atm
  private let spawn: (ActorSystem, ID, Dependency?) async throws -> VirtualActor

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
      for await virtualNode in await actorSystem.receptionist.listing(of: VirtualNode<VirtualActor, ID>.nodes) {
        self.virtualNodes.insert(virtualNode)
        self.watchTermination(of: virtualNode)
      }
    }
  }
  
  /// - Parameters:
  /// - id—external (not system) id of an actor.
  /// - dependency—only needed when spawning an actor.
  distributed public func get(id: ID, dependency: Dependency? = .none) async throws -> VirtualActor {
    for virtualNode in virtualNodes {
      if let actor = try? await virtualNode.find(id: id) {
        return actor
      }
    }
    guard let node = virtualNodes.randomElement() else {
      // There should be always a node (at least local node), if not—something sus
      throw Error.noNodesAvailable
    }
    let actor = try await self.spawn(node.actorSystem, id, dependency)
    try await node.register(actor: actor, with: id)
    return actor
  }
  
  /// Actors should be cleaned automatically, but for now unfortunately manual cleaning.
  distributed public func closeActor(for id: ID) async {
    for node in virtualNodes {
      try? await node.close(with: id)
    }
  }
  
  /// - Parameters:
  ///  - spawn—definining how an actor should be created.
  ///  Local node is created while initialising a factory.
  public init(
    actorSystem: ClusterSystem,
    spawn: @escaping (ActorSystem, ID, Dependency?) async throws -> VirtualActor
  ) async {
    self.actorSystem = actorSystem
    self.spawn = spawn
    /// At least local node should be available for transparency
    let localNode = await VirtualNode<VirtualActor, ID>(actorSystem: actorSystem)
    self.virtualNodes.insert(localNode)
    self.findVirtualNodes()
  }
}

distributed public actor VirtualNode<VirtualActor, ID>
  where VirtualActor: DistributedActor & Codable,
        ID: Hashable & Codable {
  
  public enum Error: Swift.Error {
    case noActorAvailable
  }
  
  private lazy var subactors: [ID: VirtualActor] = [:]
  
  distributed fileprivate func register(actor: VirtualActor, with id: ID) {
    self.subactors[id] = actor
  }
  
  distributed public func find(id: ID) async throws -> VirtualActor {
    guard let room = self.subactors[id] else {
      throw Error.noActorAvailable
    }
    return room
  }
  
  distributed public func close(
    with id: ID
  ) async {
    self.subactors.removeValue(forKey: id)
  }
  
  public init(
    actorSystem: ClusterSystem
  ) async {
    self.actorSystem = actorSystem
    await actorSystem
      .receptionist
      .checkIn(self, with: Self.nodes)
  }
}

extension VirtualNode {
  static var nodes: DistributedReception.Key<VirtualNode<VirtualActor, ID>> { "virtual_nodes_\(Self.self)" }
}
