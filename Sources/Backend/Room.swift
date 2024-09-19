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
  
  public init(
    actorSystem: ClusterSystem,
    info: Room.Info
  ) async {
    self.actorSystem = actorSystem
    self.state = .init(info: info)
    self.persistenceId = info.id.rawValue.uuidString
  }
  
  private func notifyEveryoneAbout(_ envelope: MessageEnvelope) async {
    let room = self
    await withTaskGroup(of: Void.self) { [state] group in
        for other in state.onlineUsers {
        group.addTask { [weak other] in
          // TODO: should we handle errors here?
          try? await other?.receive(
            envelopes: [envelope],
            from: room
          )
        }
        await group.waitForAll()
      }
    }
  }
}
