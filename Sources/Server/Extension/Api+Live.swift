import Frontend
import FoundationEssentials
import Persistence

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
