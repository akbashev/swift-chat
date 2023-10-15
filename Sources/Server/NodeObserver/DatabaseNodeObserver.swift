import Backend
import Distributed
import DistributedCluster

/**
 Not actually observer, I guess? Not sure what is proper name.
 */
distributed actor DatabaseNodeObserver: LifecycleWatch {

  enum Error: Swift.Error {
    case databaseNodeUnavailable
  }
    
  private lazy var databaseNodes: Set<DatabaseNode> = .init()
  private var listingTask: Task<Void, Never>?
  // TODO: Move logic out
  // We need reference for PostgresConnection
  private var localNode: DatabaseNode?

  distributed public func get() async throws -> DatabaseNode {
    if let databaseNode = self.databaseNodes.randomElement() { return databaseNode }
    if let localNode { return localNode }
    let databaseNode = try await DatabaseNode(actorSystem: self.actorSystem)
    self.localNode = databaseNode
    return databaseNode
  }
  
  func terminated(actor id: DistributedCluster.ActorID) async {
    guard let databaseNode = self.databaseNodes.first(where: { $0.id == id }) else { return }
    self.databaseNodes.remove(databaseNode)
  }
  
  private func findDatabaseNodes() {
    guard self.listingTask == nil else {
      actorSystem.log.info("Already looking for room pools")
      return
    }
    
    self.listingTask = Task {
      for await databaseNode in await actorSystem.receptionist.listing(of: .databaseNodes) {
        self.databaseNodes.insert(databaseNode)
        self.watchTermination(of: databaseNode)
      }
    }
  }
  
  public init(
    actorSystem: ClusterSystem
  ) {
    self.actorSystem = actorSystem
    self.findDatabaseNodes()
  }
}
