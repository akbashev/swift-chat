import Foundation
import HTTPTypes
import OpenAPIRuntime
import Sharing

struct AuthTokenMiddleware: ClientMiddleware {

  @Shared(.appStorage("authToken")) private var authToken: String?

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    guard let authToken else {
      return try await next(request, body, baseURL)
    }
    var request = request
    request.headerFields[.authorization] = "Bearer \(authToken)"
    return try await next(request, body, baseURL)
  }
}
