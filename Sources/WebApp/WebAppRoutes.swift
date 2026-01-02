import Elementary
import Foundation
import Hummingbird
import HummingbirdElementary
import Models
import Persistence

public struct WebAppRoutes: Sendable {

  private enum CookieKey {
    static let participantId = "participant_id"
  }

  enum Error: Swift.Error {
    case missingParticipant
  }

  let persistence: Persistence

  public init(persistence: Persistence) {
    self.persistence = persistence
  }

  public func register(on router: Router<BasicRequestContext>) {
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

    app.post("register") { request, _ in
      let fields = try await formFields(from: request)
      let rawName = fields["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !rawName.isEmpty else {
        return htmlResponse(RegistrationFragment(error: "Please enter a name to join."))
      }
      let participantId = UUID()
      try await persistence.create(
        .participant(
          .init(
            id: participantId,
            createdAt: .init(),
            name: rawName
          )
        )
      )
      let participant = try await persistence.getParticipant(for: participantId)
      var response = htmlResponse(LobbyFragment(participant: participant, rooms: []))
      response.headers.append(
        .init(
          name: .setCookie,
          value: "\(CookieKey.participantId)=\(participantId.uuidString); Path=/; SameSite=Lax"
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
  private func loadParticipant(from request: Request) async throws -> ParticipantModel {
    guard
      let cookies = request.headers[.cookie],
      let participantId = parseCookies(cookies)[CookieKey.participantId],
      let uuid = UUID(uuidString: participantId)
    else {
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
