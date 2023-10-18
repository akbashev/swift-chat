import Persistence
import DistributedCluster
import Distributed
import Frontend
import FoundationEssentials

/// Not quite _connection_ but will call for now.
actor HttpConnection: RestApi {
  
  let persistence: Persistence
  
  func createUser(_ request: Frontend.CreateUserRequest) async throws -> Frontend.UserResponse {
    let name = request.name
    let id = UUID()
    try await persistence.create(
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
  }
  
  func creteRoom(_ request: Frontend.CreateRoomRequest) async throws -> Frontend.RoomResponse {
    let id = UUID()
    let name = request.name
    let description = request.description
    try await persistence.create(
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
  }
  
  func searchRoom(_ request: Frontend.SearchRoomRequest) async throws -> [Frontend.RoomResponse] {
    try await persistence
      .searchRoom(query: request.query)
      .map {
        RoomResponse(
          id: $0.id,
          name: $0.name,
          description: $0.description
        )
      }
  }
  
  init(
    persistence: Persistence
  ) {
    self.persistence = persistence
  }
}
