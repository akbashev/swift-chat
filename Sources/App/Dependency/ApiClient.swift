import Foundation
import Dependencies

struct ApiClient {
  let createUser: (String) async throws -> (UserResponse)
  let createRoom: (String, String?) async throws -> (RoomResponse)
  let searchRoom: (String) async throws -> ([RoomResponse])
}

extension ApiClient: DependencyKey {
  public static var liveValue: Self {
    Self(
      createUser: { name in
        struct Request: Encodable {
          let name: String
        }
        var request = URLRequest(url: URL(string: "http://localhost:8080/user")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(Request(name: name))
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(UserResponse.self, from: data)
      },
      createRoom: { name, description in
        struct Request: Encodable {
          let name: String
          let description: String?
        }
        var request = URLRequest(url: URL(string: "http://localhost:8080/room")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(Request(name: name, description: description))
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(RoomResponse.self, from: data)
      },
      searchRoom: { query in
        struct Request: Encodable {
          let query: String
        }
        var request = URLRequest(url: URL(string: "http://localhost:8080/room/search?query=\(query)")!)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([RoomResponse].self, from: data)
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
