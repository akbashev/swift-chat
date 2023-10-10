import HummingbirdWSCore
import HummingbirdWebSocket
import HummingbirdFoundation
import FoundationEssentials
import Frontend
import Backend
import Persistence
import EventSource
import DistributedCluster
import PostgresNIO

actor WebsocketClient {
  
  private let actorSystem: ClusterSystem
  private let persistencePool: PersistencePool
  private let eventSourcePool: EventSourcePool
  private let roomPoolManager: RoomPoolManager
  private var connections: [UUID: WebsocketConnection] = [:]
  private var listeningTask: Task<Void, any Error>?

  init(
    actorSystem: ClusterSystem,
    wsBuilder: HBWebSocketBuilder,
    persistencePool: PersistencePool
  ) {
    self.actorSystem = actorSystem
    wsBuilder.addUpgrade()
    wsBuilder.add(middleware: HBLogRequestsMiddleware(.info))
    self.persistencePool = persistencePool
    self.eventSourcePool = .init(actorSystem: actorSystem)
    self.roomPoolManager = .init(actorSystem: actorSystem)
    
    let events = WebsocketApi.configure(builder: wsBuilder)
    self.listenForConnections(events: events)
  }
  
  private func listenForConnections(events: AsyncStream<WebsocketApi.Event>) {
    self.listeningTask = Task {
      for await event in events {
        try? await self.handle(event: event)
      }
    }
  }
  
  private func handle(event: WebsocketApi.Event) async throws {
    switch event {
    case .close(let info):
      await self.connections[info.userId]?.close()
      self.connections[info.userId] = .none
    case .connect(let info):
      self.connections[info.userId] = try await WebsocketConnection(
        actorSystem: self.actorSystem,
        persistence: self.persistencePool.get(),
        eventSource: self.eventSourcePool.get(),
        roomPool: self.roomPoolManager.get(),
        info: info
      )
    }
  }
}
