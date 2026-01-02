import AuthCore
import Foundation
import Hummingbird
import HummingbirdAuth
import Persistence

struct AuthConfiguration {
  enum Error: Swift.Error {
    case missingEnvironment(String)
    case invalidEnvironment(String)
  }

  let jwtSigner: JWTSigner

  init(environment: Environment) throws {
    guard let jwtSecret = environment.get("JWT_SECRET") else {
      throw Error.missingEnvironment("JWT_SECRET")
    }
    let issuer = environment.get("JWT_ISSUER") ?? "swift-chat"
    let ttlSeconds = environment.get("JWT_TTL_SECONDS").flatMap { Int($0) } ?? 3600
    guard ttlSeconds > 0 else {
      throw Error.invalidEnvironment("JWT_TTL_SECONDS must be positive")
    }

    self.jwtSigner = JWTSigner(secret: Data(jwtSecret.utf8), issuer: issuer, ttlSeconds: ttlSeconds)
  }
}

struct TokenResponse: ResponseEncodable {
  let accessToken: String
  let tokenType: String
  let expiresIn: Int
}

struct BasicParticipantAuthenticator<Context: AuthRequestContext>: AuthenticatorMiddleware where Context.Identity == ParticipantModel {
  let persistence: Persistence

  func authenticate(request: Request, context: Context) async throws -> ParticipantModel? {
    guard let basic = request.headers.basic else { return nil }
    do {
      let auth = try await persistence.getParticipantAuth(named: basic.username)
      let matches = try await PasswordHasher.verify(basic.password, hash: auth.passwordHash)
      guard matches else {
        throw HTTPError(.unauthorized, message: "Invalid credentials")
      }
      return auth.participant
    } catch {
      throw HTTPError(.unauthorized, message: "Invalid credentials")
    }
  }
}

struct JWTAuthenticator<Context: AuthRequestContext>: AuthenticatorMiddleware where Context.Identity == ParticipantModel {
  let signer: JWTSigner
  let persistence: Persistence
  let exemptPaths: Set<String>

  func authenticate(request: Request, context: Context) async throws -> ParticipantModel? {
    if exemptPaths.contains(request.uri.path) {
      return nil
    }
    guard let bearer = request.headers.bearer else {
      throw HTTPError(.unauthorized, message: "Missing bearer token")
    }
    do {
      let claims = try signer.verify(token: bearer.token)
      guard let participantId = UUID(uuidString: claims.sub) else {
        throw HTTPError(.unauthorized, message: "Invalid token subject")
      }
      return try await persistence.getParticipant(for: participantId)
    } catch {
      throw HTTPError(.unauthorized, message: "Invalid token")
    }
  }
}
