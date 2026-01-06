import Distributed
import DistributedCluster
import EventSourcing
import Foundation
import VirtualActors

public distributed actor Room {

  public typealias ActorSystem = ClusterSystem

  private var state: State

  distributed public var info: Room.Info {
    self.state.info
  }

  // MARK: `Participant` should send message, thus this is not public.
  distributed func receive(message: Message, from participant: Participant) async throws {
    /// Check if message could be handled
    switch message {
    case .join where self.state.onlineParticipants.contains(participant):
      /// Participant already joined
      throw Error.participantAlreadyJoined
    case .disconnect where !self.state.onlineParticipants.contains(participant),
      .message where !self.state.onlineParticipants.contains(participant):
      /// Participant should join first before sending messages
      throw Error.participantIsMissing
    default:
      ()
    }

    /// Now handle it
    let participantInfo = try await participant.info
    let messageEnvelope = MessageEnvelope(
      room: self.state.info,
      participant: participantInfo,
      message: message
    )
    self.actorSystem.log.info("Recieved message \(message) from participant \(participantInfo)")
    let action = Event.Action(message)
    let event = Event.participantDid(action, info: participantInfo)
    do {
      /// We're saving state by saving an event
      /// Emit function also calls `handleEvent(_:)` internally, so will update state
      /// Otherwise—don't update the state! Order and fact of saving is important.
      try await self.emit(event: event)
    } catch {
      // TODO: Retry?
      self.actorSystem.log.error("Emitting failed, reason: \(error)")
      throw error
    }
    /// after saving event, we need to update room state
    switch message {
    case .join:
      self.state.onlineParticipants.insert(participant)
      // send old messages to participant
      try? await participant.receive(
        envelopes: self.state
          .messages
          .filter { $0 != messageEnvelope },
        from: self
      )
    case .disconnect:
      self.state.onlineParticipants.remove(participant)
    default:
      break
    }
    /// notify everyone online about current message
    await self.notifyEveryoneAbout(
      messageEnvelope
    )
  }

  public init(
    actorSystem: ClusterSystem,
    info: Room.Info
  ) async throws {
    self.actorSystem = actorSystem
    self.state = .init(info: info)
    try await actorSystem
      .journal
      .register(actor: self, with: info.name)
  }

  private func notifyEveryoneAbout(_ envelope: MessageEnvelope) async {
    let onlineParticipants = self.state.onlineParticipants
    await withTaskGroup(of: Void.self) { group in
      for other in onlineParticipants {
        group.addTask { [weak other] in
          // TODO: should we handle errors here?
          try? await other?.receive(
            envelopes: [envelope],
            from: self
          )
        }
        await group.waitForAll()
      }
    }
  }
}

extension Room: EventSourced {
  distributed public func handleEvent(_ event: Event) {
    switch event {
    case .participantDid(let action, let participantInfo):
      self.state.messages
        .append(
          MessageEnvelope(
            room: self.state.info,
            participant: participantInfo,
            message: .init(action)
          )
        )
    }
  }
}

extension Room: VirtualActor {
  public static func spawn(
    on actorSystem: DistributedCluster.ClusterSystem,
    dependency: any Sendable & Codable
  ) async throws -> Room {
    /// A bit of boilerplate to check type until (associated type error)[https://github.com/swiftlang/swift/issues/74769] is fixed
    guard let dependency = dependency as? Room.Info else {
      throw VirtualActorError.spawnDependencyTypeMismatch
    }
    return try await Room(
      actorSystem: actorSystem,
      info: dependency
    )
  }
}
