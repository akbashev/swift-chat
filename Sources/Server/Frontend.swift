//import DistributedCluster
//import Backend
//import Frontend
//import FoundationEssentials
//import NIOCore
//import EventSource
//import Persistence
//import Hummingbird
//import PostgresNIO
//
//distributed actor ConnectionManager: LifecycleWatch {
//  
//  private var listingTask: Task<Void, Never>?
//
//  let persistencePool: PersistencePool
//  let eventSourcePool: EventSourcePool
//  let roomPoolManager: RoomPoolManager
//  var connections: [UUID: Connection] = [:]
//
//  init(
//    actorSystem: ClusterSystem,
//    persistencePool: PersistencePool
//  ) {
//    self.actorSystem = actorSystem
//    self.persistencePool = persistencePool
//    self.eventSourcePool = EventSourcePool(actorSystem: actorSystem)
//    self.roomPoolManager = RoomPoolManager(actorSystem: actorSystem)
//  }
//  
//  distributed func handle(
//    message: ChatMessage.Message
//  ) async throws {
//    switch self.connections[userId] {
//    case .some(let connection):
//      try await connection.handle(message: message)
//    case .none:
//      let connection = try await Connection(
//        actorSystem: self.actorSystem,
//        persistence: self.persistencePool.get(),
//        eventSource: self.eventSourcePool.get(),
//        roomPool: self.roomPoolManager.get(),
//        userId: userId,
//        roomId: roomId,
//        webSocket: websocket
//      )
//      self.connections[userId] = connection
//      try await connection.start()
//      try await connection.handle(message: message)
//    }
//  }
//  
//  func terminated(actor id: ActorID) {
//    guard let actor = self.rooms.first(where: { $0.id == id }) else { return }
//    self.rooms.remove(actor)
//  }
//  
//  private func findRooms() {
//    guard self.listingTask == nil else {
//      return self.actorSystem.log.info("Already looking for rooms")
//    }
//    
//    self.listingTask = Task {
//      for await room in await actorSystem.receptionist.listing(of: .rooms) {
//        self.watchTermination(of: room)
//      }
//    }
//  }
//}
//
