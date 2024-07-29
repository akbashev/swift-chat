import Distributed
import DistributedCluster
import EventSource
import Foundation
import VirtualActor
import EventSourcing

public distributed actor Room: EventSourced, VirtualActor {
  
  public typealias ActorSystem = ClusterSystem
  
  @ActorID.Metadata(\.persistenceID)
  var persistenceId: PersistenceID

  private var persistenceState: State
  private var onlineUsers: Set<User> = .init()
  
  distributed public var info: Room.Info {
    get async throws { self.persistenceState.info }
  }
  
  // MARK: `User` should send message, thus this is not public.
  distributed func send(_ message: Message, from user: User) async throws {
    let userInfo = try await user.info
    let messageEnvelope = MessageEnvelope(
      room: self.persistenceState.info,
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
      guard !self.onlineUsers.contains(user) else { break }
      self.onlineUsers.insert(user)
      // send old messages to user
      try? await user.send(
        envelopes: self.persistenceState
          .messages
          .filter { $0 != messageEnvelope },
        from: self
      )
    case .leave,
        .disconnect:
      self.onlineUsers.remove(user)
    default:
      break
    }
    /// notify everyone online about current message
    await self.notifyEveryoneAbout(
      messageEnvelope
    )
  }
  
  distributed public func handleEvent(_ event: Event) {
    switch event {
    case .userDid(let action, let userInfo):
      self.persistenceState.messages
        .append(
          MessageEnvelope(
            room: self.persistenceState.info,
            user: userInfo,
            message: .init(action)
          )
        )
    }
  }
  
  public init(
    actorSystem: ClusterSystem,
    info: Room.Info
  ) async {
    self.actorSystem = actorSystem
    self.persistenceState = .init(info: info)
    self.persistenceId = info.id.rawValue.uuidString
  }
  
  private func notifyEveryoneAbout(_ envelope: MessageEnvelope) async {
    await withTaskGroup(of: Void.self) { group in
      for other in self.onlineUsers {
        group.addTask { [weak other] in
          // TODO: should we handle errors here?
          try? await other?.send(
            envelopes: [envelope],
            from: self
          )
        }
        await group.waitForAll()
      }
    }
  }
}
