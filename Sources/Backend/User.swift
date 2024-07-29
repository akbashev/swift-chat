import Distributed
import DistributedCluster
import Foundation

public distributed actor User {
  
  public typealias ActorSystem = ClusterSystem
  public typealias Reply = @Sendable ([Output]) async throws -> ()

  private var state: State
  private let reply: Reply
  
  distributed public var info: User.Info {
    get async throws { self.state.info }
  }
  
  /// For Room I've made `send` function internal, with the goal to use `user.send` function publically.
  /// There are two reasons for that:
  /// 1. It's user who actually sends messages to the room.
  /// 2. Easier handle some additional logic here in the future.
  distributed public func send(message: Room.Message, to room: Room) async throws {
    try await room.send(message, from: self)
    /// You can add logic here, e.g. to store room ids where user participated.
  }
    
  /// This is also internal, user can recieve envelopes only from room.
  /// To improve a bit performance (sending history of messages)—this function can already accept an array of envelopes.
  distributed func send(envelopes: [MessageEnvelope], from room: Room) async throws {
    try await self.reply(envelopes.map { .message($0) })
    /// we can add aditional logic to send something back to the room.
  }
  
  public init(
    actorSystem: ClusterSystem,
    info: User.Info,
    reply: @escaping Reply
  ) {
    self.actorSystem = actorSystem
    self.state = .init(
      info: info
    )
    self.reply = reply
  }
}
