import Foundation

struct EventModel<Command>: Codable, Identifiable where Command: Codable {
  let id: UUID
  let createdAt: Date
  let command: Command
}
