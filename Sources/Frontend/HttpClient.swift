import HummingbirdFoundation

public enum HttpClient {
  public static func configure(
    router: HBRouterBuilder,
    api: Api
  ) {
    router.get("hello") { _ in
      return "Hello"
    }
    router.post("user") { req in
      guard let user = try? req.decode(as: CreateUserRequest.self)
      else { throw HBHTTPError(.badRequest) }
      return try await api.createUser(user)
    }
    router.post("room") { req in
      guard let room = try? req.decode(as: CreateRoomRequest.self)
      else { throw HBHTTPError(.badRequest) }
      return try await api.creteRoom(room)
    }
    router.get("room/search") { req in
      guard let query = req.uri
        .queryParameters
        .get("query", as: String.self) else { throw HBHTTPError(.badRequest) }
      return try await api.searchRoom(.init(query: query))
    }
  }
}

