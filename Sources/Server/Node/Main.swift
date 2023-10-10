import DistributedCluster
import Persistence
import EventSource
import Hummingbird
import Backend
import Frontend
import NIO
import FoundationEssentials

enum Main: Node {
  
  enum Error: Swift.Error {
    case noConnection
  }
  
  static func run(
    host: String,
    port: Int
  ) async throws {
    let mainNode = await ClusterSystem("main") {
      $0.bindHost = host
      $0.bindPort = port
    }
    let persistencePool = PersistencePool(actorSystem: mainNode)
    let app = HBApplication(
      configuration: .init(
        address: .hostname(
          mainNode.cluster.node.host,
          port: 8080
        ),
        serverName: "Frontend"
      )
    )

    app.encoder = JSONEncoder()
    app.decoder = JSONDecoder()

    Api
      .configure(
        router: app.router,
        api: .live(
          persistencePool: persistencePool
        )
      )
    let wsClient = WebsocketClient(
      actorSystem: mainNode,
      wsBuilder: app.ws,
      persistencePool: persistencePool
    )
        
    try app.start()
    try await mainNode.terminated
  }
}

extension TimeoutBasedDowningStrategySettings {
  static var serverDefault: TimeoutBasedDowningStrategySettings {
    var settings = TimeoutBasedDowningStrategySettings.default
    settings.downUnreachableMembersAfter = .seconds(1)
    return settings
  }
}
