import Hummingbird
import Foundation
import API
import Backend
import Persistence
import EventSource
import Distributed
import DistributedCluster
import PostgresNIO
import VirtualActor
import OpenAPIHummingbird
import OpenAPIRuntime
import ServiceLifecycle

struct Frontend: Service {
  
  enum Error: Swift.Error {
    case noConnection
    case noDatabaseAvailable
    case unsupportedType
    case alreadyConnected
  }
  
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
    let handler = RestApi(
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
        serverName: "frontend"
      )
    )
    app.addServices(clientServerConnectionHandler)
    try await app.run()
  }
}
