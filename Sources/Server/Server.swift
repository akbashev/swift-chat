import Distributed
import DistributedCluster
import ArgumentParser
import Frontend
import FoundationEssentials

typealias DefaultDistributedActorSystem = ClusterSystem

@main
struct Server: AsyncParsableCommand {
  
  enum Cluster: String, ExpressibleByArgument {
    case main
    case room
    case database
  }
  
  @Argument var cluster: Cluster
  @Option var host: String = "127.0.0.1"
  @Option var port: Int = 2550
  
  func run() async throws {
    try await switch self.cluster {
    case .main: run(Main.self)
    case .room: run(RoomNode.self)
    case .database: run(Database.self)
    }
  }
  
  func run(_ node: any Node.Type) async throws {
    try await node.run(host: self.host, port: self.port)
  }
}

extension Api {
  static func live(
    persistencePool: PersistencePool
  ) -> Self {
    Self(
      createUser: { [weak persistencePool] request in
        let persistence = try await persistencePool?.get()
        let name = request.name
        let id = UUID()
        try await persistence?.create(
          .user(
            .init(
              id: id,
              createdAt: .init(),
              name: request.name
            )
          )
        )
        return UserResponse(
          id: id,
          name: name
        )
      },
      creteRoom: { [weak persistencePool] request in
        let persistence = try await persistencePool?.get()
        let id = UUID()
        let name = request.name
        let description = request.description
        try await persistence?.create(
          .room(
            .init(
              id: id,
              createdAt: .init(),
              name: request.name,
              description: request.description
            )
          )
        )
        return RoomResponse(
          id: id,
          name: name,
          description: description
        )
      },
      searchRoom: { [weak persistencePool] request in
        let persistence = try await persistencePool?.get()
        let query = request.query
        let rooms = try await persistence?.searchRoom(query: query) ?? []
        return rooms.map {
          RoomResponse(
            id: $0.id,
            name: $0.name,
            description: $0.description
          )
        }
      }
    )
  }
}
