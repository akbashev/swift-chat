import Frontend
import FoundationEssentials
import Persistence

extension Api {
  static func live(
    databaseNodeObserver: DatabaseNodeObserver
  ) -> Self {
    Self(
      createUser: { [weak databaseNodeObserver] request in
        let persistence = try await databaseNodeObserver?.get().getPersistence()
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
      creteRoom: { [weak databaseNodeObserver] request in
        let persistence = try await databaseNodeObserver?.get().getPersistence()
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
      searchRoom: { [weak databaseNodeObserver] request in
        let persistence = try await databaseNodeObserver?.get().getPersistence()
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
