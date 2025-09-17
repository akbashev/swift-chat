import DistributedCluster
import ServiceLifecycle

struct Daemon: Service {

  func run() async throws {
    try await ClusterSystem.startClusterDaemon().system.terminated
  }
}
