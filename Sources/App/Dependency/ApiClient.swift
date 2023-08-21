import Foundation
import Dependencies

struct ApiClient {
  let createUser: (String, UUID) async throws -> (UserResponse)
  let connectToRoom: (String) async throws -> (RoomResponse)
}

extension ApiClient: DependencyKey {
  public static var liveValue: Self {
    Self(
      createUser: { name, uuid in
        struct Request: Encodable {
          let id: String
          let name: String
        }
        var request = URLRequest(url: URL(string: "http://localhost:8080/user")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(Request(id: uuid.uuidString, name: name))
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(UserResponse.self, from: data)
      },
      connectToRoom: { name in
        do {
          let request = URLRequest(url: URL(string: "http://localhost:8080/room?name=\(name)")!)
          let (data, _) = try await URLSession.shared.data(for: request)
          return try JSONDecoder().decode(RoomResponse.self, from: data)
        } catch {
          struct Request: Encodable {
            let name: String
          }
          var request = URLRequest(url: URL(string: "http://localhost:8080/room")!)
          request.httpMethod = "POST"
          request.httpBody = try JSONEncoder().encode(Request(name: name))
          let (data, _) = try await URLSession.shared.data(for: request)
          return try JSONDecoder().decode(RoomResponse.self, from: data)
        }
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
