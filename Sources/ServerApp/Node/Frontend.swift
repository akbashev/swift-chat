import Backend
import Distributed
import DistributedCluster
import Foundation
import Hummingbird
import HummingbirdWSCompression
import HummingbirdWebSocket
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
    let userConnectionManager = UserRoomConnections(
      actorSystem: self.clusterSystem,
      logger: Logger(label: "UserRoomConnections"),
      persistence: persistence
    )
    let router = Router()
    let handler = Api(
      userRoomConnections: userConnectionManager,
      persistence: persistence
    )
    try handler.registerHandlers(on: router)
    // Separate router for websocket upgrade
    let wsRouter = Router(context: BasicWebSocketRequestContext.self)
    wsRouter.add(middleware: LogRequestsMiddleware(.debug))
    wsRouter.ws("chat/ws") { request, context in
      try await handler.shouldUpgrade(request: request, context: context)
    } onUpgrade: { inbound, outbound, context in
      try await handler.onUpgrade(inbound: inbound, outbound: outbound, context: context)
    }
    var app = Application(
      router: router,
      server: .http1WebSocketUpgrade(
        webSocketRouter: wsRouter,
        configuration: .init(extensions: [.perMessageDeflate()])
      ),
      configuration: .init(
        address: .hostname(
          self.clusterSystem.cluster.node.host,
          port: 8080
        ),
        serverName: self.clusterSystem.name
      )
    )
    app.addServices(
      userConnectionManager
    )
    try await app.run()
  }
}
