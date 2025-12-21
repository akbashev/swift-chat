import Foundation

actor Cache: Persistable {

  private struct Data: Equatable {
    var participants: Set<ParticipantModel> = []
    var rooms: Set<RoomModel> = []
  }

  private var data: Data = .init()

  func create(input: Persistence.Input) throws {
    switch input {
    case .participant(let participant):
      self.data.participants
        .insert(participant)
    case .room(let room):
      self.data.rooms
        .insert(room)
    }
  }

  func update(input: Persistence.Input) throws {
    switch input {
    case .participant(let participant):
      self.data.participants
        .insert(participant)
    case .room(let room):
      self.data.rooms
        .insert(room)
    }
  }

  func getParticipant(for id: UUID) throws -> ParticipantModel {
    guard let participantInfo = self.data.participants.first(where: { $0.id == id }) else {
      throw Persistence.Error.participantMissing(id: id)
    }
    return participantInfo
  }

  func getRoom(for id: UUID) throws -> RoomModel {
    guard let roomInfo = self.data.rooms.first(where: { $0.id == id }) else {
      throw Persistence.Error.roomMissing(id: id)
    }
    return roomInfo
  }

  func searchRoom(query: String) async throws -> [RoomModel] {
    self.data.rooms.filter { $0.name.contains(query) }
  }
}

extension ParticipantModel: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.id.uuidString)
  }
}

extension RoomModel: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.id.uuidString)
  }
}
