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
      guard let user = try? req.decode(as: Api.CreateUserRequest.self)
      else { throw HBHTTPError(.badRequest) }
      return try await api.createUser(user)
    }
    self.router.post("room") { req in
      guard let room = try? req.decode(as: Api.CreateRoomRequest.self)
      else { throw HBHTTPError(.badRequest) }
      return try await api.creteRoom(room)
    }
  }
  
  init(
    router: HBRouterBuilder
  ) {
    self.router = router
  }
}

