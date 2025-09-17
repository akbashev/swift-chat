import Backend
import Distributed
import DistributedCluster
import Foundation
import Hummingbird
import OpenAPIHummingbird
import OpenAPIRuntime
import Persistence
import PostgresNIO
import ServiceLifecycle

struct Frontend: Service {

  let clusterSystem: ClusterSystem

  init(clusterSystem: ClusterSystem) {
    self.clusterSystem = clusterSystem
  }

  func run() async throws {
    let env = Environment()
    let config = try PostgresConfig(
      host: self.clusterSystem.cluster.node.endpoint.host,
      environment: env
    ).generate()
    let persistence = try await Persistence(
      type: .postgres(config)
    )
    let clientServerConnectionHandler = ClientServerConnectionHandler(
      actorSystem: self.clusterSystem,
      persistence: persistence
    )
    let router = Router()
    let handler = Api(
      clientServerConnectionHandler: clientServerConnectionHandler,
      persistence: persistence
    )
    try handler.registerHandlers(on: router)
    var app = Application(
      router: router,
      configuration: .init(
        address: .hostname(
          self.clusterSystem.cluster.node.host,
          port: 8080
        ),
        serverName: self.clusterSystem.name
      )
    )
    app.addServices(clientServerConnectionHandler)
    try await app.run()
  }
}
