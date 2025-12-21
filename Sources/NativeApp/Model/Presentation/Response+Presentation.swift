import Models

extension ParticipantResponse {
  init(_ participant: ParticipantPresentation) {
    self.init(id: participant.id.uuidString, name: participant.name)
  }
}

extension RoomResponse {
  init(_ room: RoomPresentation) {
    self.init(id: room.id.uuidString, name: room.name, description: room.description)
  }
}
