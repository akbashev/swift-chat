import ServiceLifecycle
import DistributedCluster

/// Not sure if I need it, but will put it for now.
protocol Node: Service {
  var name: String { get }
  var host: String { get set }
  var port: Int { get set }
  func run(on clusterSystem: ClusterSystem) async throws
}

extension Node {
  func run() async throws {
    let clusterSystem = await ClusterSystem(name) {
      $0.bindHost = host
      $0.bindPort = port
      $0.installPlugins()
    }
    try await self.run(
      on: clusterSystem
    )
  }
}
