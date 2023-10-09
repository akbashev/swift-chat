import DistributedCluster
import Persistence
import EventSource
import Hummingbird
import Backend
import Frontend
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
    let connectionManager = try await ConnectionManager(
      actorSystem: mainNode
    )
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

    let httpClient = HttpClient(router: app.router)
    let wsClient = WebsocketClient(wsBuilder: app.ws)
    
    await httpClient.configure(api: connectionManager.api)
    await wsClient.configure(api: connectionManager.api)
    
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
