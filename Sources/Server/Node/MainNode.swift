import DistributedCluster
import Persistence
import EventSource
import Hummingbird
import Backend
import Frontend
import FoundationEssentials

enum MainNode: Node {
  static func run(
    host: String,
    port: Int
  ) async throws {
    let mainNode = await ClusterSystem("main") {
      $0.autoLeaderElection = .lowestReachable(minNumberOfMembers: 1)
      $0.bindHost = host
      $0.bindPort = port
      $0.downingStrategy = .timeout(.default)
    }

    let persistencePool = PersistencePool(actorSystem: mainNode)
    let eventSourcePool = EventSourcePool(actorSystem: mainNode)
    let roomsPoolManager = RoomPoolManager(actorSystem: mainNode)
    
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
          
    let api: Api = Api.live(
      node: mainNode,
      persistencePool: persistencePool,
      handle: { connection in
        do {
          let persistence = try await persistencePool.get()
          let eventSource = try await eventSourcePool.get()
          let roomPool = try await roomsPoolManager.get()
          return await ConnectionManager.handle(
            actorSystem: mainNode,
            connection: connection,
            persistence: persistence,
            eventSource: eventSource,
            roomPool: roomPool
          )
        } catch {
          mainNode.log.error("\(error)")
        }
      }
    )
    HttpClient.configure(
      router: app.router,
      api: api
    )
    WebsocketClient.configure(
      wsBuilder: app.ws,
      api: api
    )
    try app.start()
    try await mainNode.terminated
  }
}
