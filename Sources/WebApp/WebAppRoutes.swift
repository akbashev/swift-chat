import AuthCore
import Elementary
import Foundation
import Hummingbird
import HummingbirdElementary
import Models
import Persistence

public struct WebAppRoutes: Sendable {

  private enum CookieKey {
    static let participantId = "participant_id"
    static let authToken = "auth_token"
  }

  enum Error: Swift.Error {
    case missingParticipant
  }

  let persistence: Persistence
  let jwtSigner: JWTSigner

  public init(persistence: Persistence, jwtSigner: JWTSigner) {
    self.persistence = persistence
    self.jwtSigner = jwtSigner
  }

  public func register<Context: RequestContext>(on router: Router<Context>) {
    let app = router.group("app")

    app.get("") { request, _ in
      let participant = try? await loadParticipant(from: request)
      if let participant {
        return htmlResponse(Page(pageContent: LobbyFragment(participant: participant, rooms: []), participant: participant))
      }
      return htmlResponse(Page(pageContent: RegistrationFragment(error: nil), participant: nil))
    }

    app.get("lobby") { request, _ in
      let participant = try? await loadParticipant(from: request)
      guard let participant else {
        return htmlResponse(RegistrationFragment(error: nil))
      }
      return htmlResponse(LobbyFragment(participant: participant, rooms: []))
    }

    app.get("register") { _, _ in
      htmlResponse(RegistrationFragment(error: nil))
    }

    app.get("login") { _, _ in
      htmlResponse(LoginFragment(error: nil))
    }

    app.post("register") { request, _ in
      let fields = try await formFields(from: request)
      let rawName = fields["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let rawPassword = fields["password"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !rawName.isEmpty else {
        return htmlResponse(RegistrationFragment(error: "Please enter a name to join."))
      }
      guard rawPassword.count >= 6 else {
        return htmlResponse(RegistrationFragment(error: "Password must be at least 6 characters."))
      }
      switch try await resolveRegistration(name: rawName, password: rawPassword) {
      case .success(let participant):
        return responseForParticipant(participant)
      case .conflict:
        return htmlResponse(RegistrationFragment(error: "Name is already taken. Please choose another."))
      }
    }

    app.post("login") { request, _ in
      let fields = try await formFields(from: request)
      let rawName = fields["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let rawPassword = fields["password"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !rawName.isEmpty else {
        return htmlResponse(LoginFragment(error: "Please enter your name."))
      }
      guard !rawPassword.isEmpty else {
        return htmlResponse(LoginFragment(error: "Please enter your password."))
      }
      switch try await resolveLogin(name: rawName, password: rawPassword) {
      case .success(let participant):
        return responseForParticipant(participant)
      case .invalidCredentials:
        return htmlResponse(LoginFragment(error: "Invalid credentials."))
      }
    }

    app.post("logout") { _, _ in
      var response = htmlResponse(RegistrationFragment(error: nil))
      response.headers.append(
        .init(
          name: .setCookie,
          value: "\(CookieKey.participantId)=; Path=/; Max-Age=0; SameSite=Lax"
        )
      )
      response.headers.append(
        .init(
          name: .setCookie,
          value: "\(CookieKey.authToken)=; Path=/; Max-Age=0; SameSite=Lax; HttpOnly"
        )
      )
      response.headers.append(
        .init(
          name: .init("HX-Redirect")!,
          value: "/app"
        )
      )
      return response
    }

    app.get("rooms/search") { request, _ in
      let queryValue = request.uri.queryParameters["query"].map { String($0) } ?? ""
      let query = queryValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !query.isEmpty else {
        return htmlResponse(RoomsFragment(rooms: [], query: ""))
      }
      let rooms = try await persistence.searchRoom(query: query)
      return htmlResponse(RoomsFragment(rooms: rooms, query: query))
    }

    app.post("rooms") { request, _ in
      let participant = try? await loadParticipant(from: request)
      guard let participant else {
        return htmlResponse(RegistrationFragment(error: "Please register before creating a room."))
      }
      let fields = try await formFields(from: request)
      let rawName = fields["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !rawName.isEmpty else {
        return htmlResponse(
          LobbyFragment(
            participant: participant,
            rooms: [],
            error: "Room name is required."
          )
        )
      }
      let description = fields["description"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      let roomId = UUID()
      try await persistence.create(
        .room(
          .init(
            id: roomId,
            createdAt: .init(),
            name: rawName,
            description: description?.isEmpty == true ? nil : description
          )
        )
      )
      let room = try await persistence.getRoom(for: roomId)
      return htmlResponse(RoomFragment(participant: participant, room: room))
    }

    app.post("rooms/join") { request, _ in
      let participant = try? await loadParticipant(from: request)
      guard let participant else {
        return htmlResponse(RegistrationFragment(error: "Please register before joining a room."))
      }
      let fields = try await formFields(from: request)
      guard
        let rawRoomId = fields["room_id"],
        let roomId = UUID(uuidString: rawRoomId)
      else {
        return htmlResponse(
          LobbyFragment(
            participant: participant,
            rooms: [],
            error: "Select a room to join."
          )
        )
      }
      let room = try await persistence.getRoom(for: roomId)
      return htmlResponse(RoomFragment(participant: participant, room: room))
    }
  }

}

extension WebAppRoutes {
  private enum RegistrationOutcome {
    case success(ParticipantModel)
    case conflict
  }

  private enum LoginOutcome {
    case success(ParticipantModel)
    case invalidCredentials
  }

  private func resolveRegistration(
    name: String,
    password: String
  ) async throws -> RegistrationOutcome {
    do {
      _ = try await persistence.getParticipantAuth(named: name)
      return .conflict
    } catch Persistence.Error.participantMissing(name:) {
      let participantId = UUID()
      let passwordHash = try await PasswordHasher.hash(password)
      try await persistence.create(
        .participant(
          .init(
            id: participantId,
            createdAt: .init(),
            name: name,
            passwordHash: passwordHash
          )
        )
      )
      let participant = try await persistence.getParticipant(for: participantId)
      return .success(participant)
    }
  }

  private func resolveLogin(
    name: String,
    password: String
  ) async throws -> LoginOutcome {
    do {
      let auth = try await persistence.getParticipantAuth(named: name)
      let matches = try await PasswordHasher.verify(password, hash: auth.passwordHash)
      return matches ? .success(auth.participant) : .invalidCredentials
    } catch {
      return .invalidCredentials
    }
  }

  private func responseForParticipant(_ participant: ParticipantModel) -> HTMLResponse {
    let token = (try? jwtSigner.sign(subject: participant.id.uuidString)) ?? ""
    var response = htmlResponse(LobbyFragment(participant: participant, rooms: []))
    response.headers.append(
      .init(
        name: .setCookie,
        value: "\(CookieKey.participantId)=\(participant.id.uuidString); Path=/; SameSite=Lax"
      )
    )
    response.headers.append(
      .init(
        name: .setCookie,
        value: "\(CookieKey.authToken)=\(token); Path=/; SameSite=Lax; HttpOnly"
      )
    )
    response.headers.append(
      .init(
        name: .init("HX-Redirect")!,
        value: "/app"
      )
    )
    return response
  }

  private func loadParticipant(from request: Request) async throws -> ParticipantModel {
    guard
      let cookies = request.headers[.cookie],
      let token = parseCookies(cookies)[CookieKey.authToken]
    else {
      throw Error.missingParticipant
    }
    let claims = try jwtSigner.verify(token: token)
    guard let uuid = UUID(uuidString: claims.sub) else {
      throw Error.missingParticipant
    }
    return try await persistence.getParticipant(for: uuid)
  }

  private func formFields(from request: Request) async throws -> [String: String] {
    var buffer = ByteBuffer()
    var iterator = request.body.makeAsyncIterator()
    while let chunk = try await iterator.next() {
      var chunk = chunk
      buffer.writeBuffer(&chunk)
    }
    let body = buffer.getString(at: 0, length: buffer.readableBytes) ?? ""
    return parseURLEncoded(body)
  }

  private func parseCookies(_ raw: String) -> [String: String] {
    var values: [String: String] = [:]
    for part in raw.split(separator: ";") {
      let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
      guard pair.count == 2 else { continue }
      values[pair[0]] = pair[1]
    }
    return values
  }

  private func parseURLEncoded(_ raw: String) -> [String: String] {
    var values: [String: String] = [:]
    for part in raw.split(separator: "&") {
      let pair = part.split(separator: "=", maxSplits: 1)
      let key = pair.first.map { decodeURIComponent(String($0)) } ?? ""
      let value = pair.count > 1 ? decodeURIComponent(String(pair[1])) : ""
      guard !key.isEmpty else { continue }
      values[key] = value
    }
    return values
  }

  private func decodeURIComponent(_ value: String) -> String {
    value
      .replacingOccurrences(of: "+", with: " ")
      .removingPercentEncoding ?? value
  }

  private func htmlResponse(_ html: some HTML & Sendable) -> HTMLResponse {
    HTMLResponse { html }
  }

  public static func renderMessageUpdate(
    _ message: ChatMessage,
    currentUserId: UUID
  ) -> String? {
    switch message.message {
    case .HeartbeatMessage:
      return nil
    default:
      return MessageUpdate(
        message: message,
        currentUserId: currentUserId.uuidString
      ).render()
    }
  }
}
