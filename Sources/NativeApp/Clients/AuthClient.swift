import Dependencies
import Foundation
import Sharing

public struct AuthToken: Decodable, Sendable {
  let accessToken: String
  let tokenType: String
  let expiresIn: Int
}

struct AuthClient: Sendable {
  var token: @Sendable (_ username: String, _ password: String) async throws -> AuthToken
}

extension AuthClient: DependencyKey {
  static let liveValue: AuthClient = {
    @Shared(.appStorage("host")) var host: String?
    let baseUrl = host ?? "http://localhost:8080"
    return AuthClient { username, password in
      var request = URLRequest(url: URL(string: baseUrl)!.appendingPathComponent("auth/token"))
      request.httpMethod = "POST"
      let credentials = "\(username):\(password)"
      let encoded = Data(credentials.utf8).base64EncodedString()
      request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      guard (200..<300).contains(httpResponse.statusCode) else {
        throw URLError(.userAuthenticationRequired)
      }
      return try JSONDecoder().decode(AuthToken.self, from: data)
    }
  }()
}

extension DependencyValues {
  var authClient: AuthClient {
    get { self[AuthClient.self] }
    set { self[AuthClient.self] = newValue }
  }
}
