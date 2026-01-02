import Elementary
import ElementaryHTMX
import ElementaryHTMXWS
import Models
import Persistence

struct Page<Content: HTML & Sendable>: HTMLDocument, Sendable {
  let pageContent: Content
  let participant: ParticipantModel?

  var title: String { "Swift Chat" }

  var head: some HTML {
    meta(.charset(.utf8))
    meta(.name("viewport"), .content("width=device-width, initial-scale=1, viewport-fit=cover"))
    script(.src("/htmx.min.js")) {}
    script(.src("/htmxws.min.js")) {}
    link(.href("/app.css"), .rel(.stylesheet))
  }

  var body: some HTML {
    HeaderView(participant: participant)
    main(.class("container app-main"), .id("main")) {
      pageContent
    }
  }
}

struct HeaderView: HTML, Sendable {
  let participant: ParticipantModel?

  var body: some HTML {
    header(.class("container app-header")) {
      div {
        h2 { "Swift Chat" }
        p { "HTMX server-rendered rooms" }
      }
      if let participant {
        div(.class("status-pill")) {
          span(.class("status-dot")) {}
          span { "Signed in as \(participant.name)" }
        }
      }
    }
  }
}

struct RegistrationFragment: HTML, Sendable {
  let error: String?

  var body: some HTML {
    section(.class("glass-card")) {
      if let error {
        small { error }
      }
      h3 { "Create your profile" }
      p(.class("subtle")) { "Pick a name to join the rooms." }
      form(
        .hx.post("/app/register"),
        .hx.target("#main"),
        .hx.swap(.innerHTML)
      ) {
        div(.class("form-row")) {
          input(
            .type(.text),
            .name("name"),
            .placeholder("Display name"),
            .autocomplete("name")
          )
          button(.type(.submit)) { "Join chat" }
        }
      }
    }
  }
}

struct LobbyFragment: HTML, Sendable {
  let participant: ParticipantModel
  let rooms: [RoomModel]
  let error: String?

  init(participant: ParticipantModel, rooms: [RoomModel], error: String? = nil) {
    self.participant = participant
    self.rooms = rooms
    self.error = error
  }

  var body: some HTML {
    section(.class("glass-card")) {
      if let error {
        small { error }
      }
      h3 { "Find a room" }
      p(.class("subtle")) { "Search by name or topic, or create your own." }
      div(.class("form-row")) {
        input(
          .type(.text),
          .name("query"),
          .placeholder("Search by name"),
          .hx.get("/app/rooms/search"),
          .hx.trigger(.event(.keyup).changed().delay("350ms")),
          .hx.target("#room-results"),
          .hx.include("this")
        )
      }
      div(.id("room-results")) {
        RoomsFragment(rooms: rooms, query: "")
      }
      hr()
      div {
        h4 { "Create a new room" }
        form(
          .hx.post("/app/rooms"),
          .hx.target("#main"),
          .hx.swap(.innerHTML)
        ) {
          div(.class("form-row")) {
            input(
              .type(.text),
              .name("name"),
              .placeholder("Room name"),
              .required
            )
            input(
              .type(.text),
              .name("description"),
              .placeholder("Description (optional)")
            )
            button(.type(.submit)) { "Create and join" }
          }
        }
      }
    }
  }
}

struct RoomsFragment: HTML, Sendable {
  let rooms: [RoomModel]
  let query: String

  var body: some HTML {
    if rooms.isEmpty {
      let message =
        query.isEmpty
        ? "Start by searching for a room."
        : "No rooms match your search yet."
      p(.class("subtle")) { message }
    } else {
      div(.class("room-grid")) {
        ForEach(rooms) { room in
          RoomCard(room: room)
        }
      }
    }
  }
}

struct RoomCard: HTML, Sendable {
  let room: RoomModel

  var body: some HTML {
    article(.class("glass-card")) {
      div(.class("row")) {
        div(.class("grow")) {
          h4 { room.name }
          p(.class("subtle")) { room.description ?? "No description." }
        }
        form(
          .hx.post("/app/rooms/join"),
          .hx.target("#main"),
          .hx.swap(.innerHTML)
        ) {
          input(.type(.hidden), .name("room_id"), .value(room.id.uuidString))
          button(.type(.submit)) { "Join" }
        }
      }
    }
  }
}

struct RoomFragment: HTML, Sendable {
  let participant: ParticipantModel
  let room: RoomModel

  var body: some HTML {
    section(
      .class("glass-card chat-shell"),
      .hx.ext(.ws),
      .ws.connect("/app/chat/ws?participant_id=\(participant.id.uuidString)&room_id=\(room.id.uuidString)"),
      .hx.target("#message-list")
    ) {
      div(.class("row")) {
        button(
          .hx.get("/app/lobby"),
          .hx.target("#main"),
          .hx.swap(.innerHTML)
        ) { "Back" }
        div {
          h3 { room.name }
          div(.class("status-pill")) {
            span(.class("status-dot")) {}
            span { "Connected" }
          }
        }
      }
      div(.id("message-list"), .class("message-list")) {
        p(.class("subtle")) { "No messages yet. Say hello." }
      }
      form(.ws.send) {
        div(.class("form-row")) {
          input(
            .type(.text),
            .name("message"),
            .placeholder("Type a message"),
            .autocomplete(.off)
          )
          button(.type(.submit)) { "Send" }
        }
      }
    }
  }
}

struct MessageUpdate: HTML, Sendable {
  let message: ChatMessage
  let currentUserId: String

  var body: some HTML {
    switch message.message {
    case .JoinMessage:
      div(
        .hx.swapOOB(.beforeEnd, "#message-list")
      ) {
        div(.class("message")) {
          strong { "\(message.participant.name) joined the chat." }
        }
      }
    case .DisconnectMessage:
      div(
        .hx.swapOOB(.beforeEnd, "#message-list")
      ) {
        div(.class("message")) {
          strong { "\(message.participant.name) left the chat." }
        }
      }
    case .TextMessage(let text):
      if message.participant.id == currentUserId {
        div(
          .hx.swapOOB(.beforeEnd, "#message-list")
        ) {
          div(.class("message me")) {
            strong { "You" }
            div(.class("message-bubble")) { text.content }
          }
        }
      } else {
        div(
          .hx.swapOOB(.beforeEnd, "#message-list")
        ) {
          div(.class("message")) {
            strong { message.participant.name }
            div(.class("message-bubble")) { text.content }
          }
        }
      }
    case .HeartbeatMessage:
      EmptyHTML()
    }
  }
}
