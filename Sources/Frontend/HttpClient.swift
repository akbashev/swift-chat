import HummingbirdFoundation

class HttpClient {
  
  private let router: HBRouterBuilder
  
  func configure(
    api: Api
  ) {
    self.router.get("hello") { _ in
      return "Hello"
    }
    self.router.post("user") { req in
      guard let user = try? req.decode(as: CreateUserRequest.self)
      else { throw HBHTTPError(.badRequest) }
      return try await api.createUser(user)
    }
    self.router.post("room") { req in
      guard let room = try? req.decode(as: CreateRoomRequest.self)
      else { throw HBHTTPError(.badRequest) }
      return try await api.creteRoom(room)
    }
    self.router.get("room/search") { req in
      guard let query = req.uri
        .queryParameters
        .get("query", as: String.self) else { throw HBHTTPError(.badRequest) }
      return try await api.searchRoom(.init(query: query))
    }
  }
  
  init(
    router: HBRouterBuilder
  ) {
    self.router = router
  }
}

