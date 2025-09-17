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

  // MARK: `User` should send message, thus this is not public.
  distributed func receive(message: Message, from user: User) async throws {
    let userInfo = try await user.info
    let messageEnvelope = MessageEnvelope(
      room: self.state.info,
      user: userInfo,
      message: message
    )
    self.actorSystem.log.info("Recieved message \(message) from user \(userInfo)")
    let action = Event.Action(message)
    let event = Event.userDid(action, info: userInfo)
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
    /// after saving event, we need to update other states
    switch message {
    case .join:
      /// Let's double check not to send old messages twice
      guard !self.state.onlineUsers.contains(user) else { break }
      self.state.onlineUsers.insert(user)
      // send old messages to user
      try? await user.receive(
        envelopes: self.state
          .messages
          .filter { $0 != messageEnvelope },
        from: self
      )
    case .leave,
      .disconnect:
      self.state.onlineUsers.remove(user)
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
  ) async {
    self.actorSystem = actorSystem
    self.state = .init(info: info)
  }

  private func notifyEveryoneAbout(_ envelope: MessageEnvelope) async {
    let onlineUsers = self.state.onlineUsers
    await withTaskGroup(of: Void.self) { group in
      for other in onlineUsers {
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
    case .userDid(let action, let userInfo):
      self.state.messages
        .append(
          MessageEnvelope(
            room: self.state.info,
            user: userInfo,
            message: .init(action)
          )
        )
    }
  }
}

extension Room: VirtualActor {

  distributed public var persistenceID: PersistenceID { self.info.name }

  public static func spawn(
    on actorSystem: DistributedCluster.ClusterSystem,
    dependency: any Sendable & Codable
  ) async throws -> Room {
    /// A bit of boilerplate to check type until (associated type error)[https://github.com/swiftlang/swift/issues/74769] is fixed
    guard let dependency = dependency as? Room.Info else {
      throw VirtualActorError.spawnDependencyTypeMismatch
    }
    return await Room(
      actorSystem: actorSystem,
      info: dependency
    )
  }
}
