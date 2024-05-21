import Foundation
import Dependencies
import ComposableArchitecture

@DependencyClient
struct ApiClient {
  var createUser: (_ name: String) async throws -> (UserResponse)
  var createRoom: (_ name: String, _ description: String?) async throws -> (RoomResponse)
  var searchRoom: (_ query: String) async throws -> ([RoomResponse])
}

extension ApiClient {
  static let decoder: JSONDecoder = .init()
  static let encoder: JSONEncoder = .init()

  enum Error: Swift.Error {
    case couldNotBuildRequest
  }
  
  enum Path: String {
    case user
    case room
    case roomSearch = "room/search"
  }
  
  enum Method: String {
    case get = "GET"
    case post = "POST"
  }
  
  static func generateRequest(
    baseUrl: String,
    path: Path,
    method: Method = .get,
    query: [String: String]? = .none,
    body: (any Encodable)? = .none
  ) throws -> URLRequest {
    guard
      var baseUrlComponents = URLComponents(
        string: baseUrl
      )
    else { throw Error.couldNotBuildRequest }
    baseUrlComponents.path = "/\(path.rawValue)"
    if let query {
      baseUrlComponents.queryItems = query.map { URLQueryItem(name: $0, value: $1) }
    }
    guard
      let url = baseUrlComponents.url
    else { throw Error.couldNotBuildRequest }
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    if let body {
      request.httpBody = try ApiClient.encoder.encode(body)
    }
    return request
  }
  
  static func execute<D: Decodable>(
    _ request: URLRequest
  ) async throws -> D {
    let (data, response) = try await URLSession.shared.data(for: request)
    return try ApiClient.decoder.decode(D.self, from: data)
  }
}

extension ApiClient: DependencyKey {
  public static var liveValue: Self {
    @Shared(.appStorage("host")) var host: String?
    
    let baseUrl = host ?? "http://localhost:8080"
    return Self(
      createUser: { name in
        struct Request: Encodable {
          let name: String
        }
        return try await execute(
          Self.generateRequest(
            baseUrl: baseUrl,
            path: .user,
            method: .post,
            body: Request(name: name)
          )
        )
      },
      createRoom: { name, description in
        struct Request: Encodable {
          let name: String
          let description: String?
        }
        return try await execute(
          Self.generateRequest(
            baseUrl: baseUrl,
            path: .room,
            method: .post,
            body: Request(
              name: name,
              description: description
            )
          )
        )
      },
      searchRoom: { query in
        try await execute(
          Self.generateRequest(
            baseUrl: baseUrl,
            path: .roomSearch,
            query: ["query": query]
          )
        )
      }
    )
  }
}

extension DependencyValues {
  var apiClient: ApiClient {
    get { self[ApiClient.self] }
    set { self[ApiClient.self] = newValue }
  }
}
