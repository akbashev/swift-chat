import Foundation

actor Cache: Persistable {

  private struct Data: Equatable {
    var participants: Set<ParticipantModel> = []
    var rooms: Set<RoomModel> = []
  }

  private var data: Data = .init()
  private var authData: AuthData = .init()

  private struct AuthData: Equatable {
    struct Record: Equatable {
      let id: UUID
      let passwordHash: String
    }

    var participantsByName: [String: Record] = [:]
  }

  func create(input: Persistence.Input) throws {
    switch input {
    case .participant(let participant):
      let model = ParticipantModel(
        id: participant.id,
        createdAt: participant.createdAt,
        name: participant.name
      )
      self.data.participants
        .insert(model)
      self.authData.participantsByName[participant.name] = .init(
        id: participant.id,
        passwordHash: participant.passwordHash
      )
    case .participantUpdate:
      break
    case .room(let room):
      self.data.rooms
        .insert(room)
    case .roomUpdate:
      break
    }
  }

  func update(input: Persistence.Input) throws {
    switch input {
    case .participantUpdate(let participant):
      self.data.participants
        .insert(participant)
    case .participant:
      break
    case .roomUpdate(let room):
      self.data.rooms
        .insert(room)
    case .room:
      break
    }
  }

  func getParticipant(for id: UUID) throws -> ParticipantModel {
    guard let participantInfo = self.data.participants.first(where: { $0.id == id }) else {
      throw Persistence.Error.participantMissing(id: id)
    }
    return participantInfo
  }

  func getParticipant(named name: String) throws -> ParticipantModel {
    guard let participantInfo = self.data.participants.first(where: { $0.name == name }) else {
      throw Persistence.Error.participantMissing(name: name)
    }
    return participantInfo
  }

  func getParticipantAuth(named name: String) async throws -> ParticipantAuth {
    guard let auth = self.authData.participantsByName[name] else {
      throw Persistence.Error.participantMissing(name: name)
    }
    let participant = try self.getParticipant(for: auth.id)
    return ParticipantAuth(participant: participant, passwordHash: auth.passwordHash)
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
