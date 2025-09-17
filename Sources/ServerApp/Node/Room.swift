import Backend
import DistributedCluster
import ServiceLifecycle
import VirtualActors

struct Room: Service {

  let clusterSystem: ClusterSystem

  func run() async throws {
    let virtualNode = await VirtualNode(
      actorSystem: self.clusterSystem
    )
    try await virtualNode.actorSystem.terminated
  }
}
