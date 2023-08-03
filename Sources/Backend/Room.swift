import Distributed
import DistributedCluster
import Models
import Store

public distributed actor Room {
  
  public typealias ActorSystem = ClusterSystem
  
  private var state: State
  private var store: Store
  
  distributed func message(_ message: Message, from user: User) async throws {
    let message: MessageInfo = try await MessageInfo(
      room: self.state.info,
      user: user.getUserInfo(),
      message: message
    )
    try await self.store.save(.message(message))
    self.state.messages.append(message)
    switch message.message {
      case .join:
        self.state.users.insert(user)
        // TODO: add logic to this messages
      case .message,
          .disconnect:
        try check(user: user)
      case .leave:
        self.state.users.remove(user)
    }
    self.notifyOthersAbout(
      message: message.message,
      from: user
    )
  }
  
  distributed public func getRoomInfo() -> RoomInfo {
    self.state.info
  }
  
  distributed public func getMessages() -> [MessageInfo] {
    self.state.messages
  }
  
  public init(
    actorSystem: ClusterSystem,
    roomId: RoomInfo.ID,
    store: Store
  ) async throws {
    self.actorSystem = actorSystem
    let roomInfo = try await store.getRoom(with: roomId)
    let messages = try await store.getMessages(for: roomId)
    self.state = .init(
      info: roomInfo,
      messages: messages
    )
    self.store = store
    await actorSystem.receptionist.checkIn(self, with: .rooms)
  }
  
  private func check(user: User) throws {
    guard self.state.users.contains(user) else { throw Room.Error.userIsMissing }
  }
  
  // non-structured
  private func notifyOthersAbout(message: Message, from user: User) {
    Task {
      await withThrowingTaskGroup(of: Void.self) { group in
        for other in self.state.users where user != other {
          group.addTask {
            try await other.notify(message, user: user, from: self)
          }
        }
      }
    }
  }
}

extension Room {
  
  public enum Error: Swift.Error {
    case userIsMissing
  }

  struct State: Equatable {
    let info: RoomInfo
    var users: Set<User> = .init()
    var messages: [MessageInfo] = .init()
  }
}

extension DistributedReception.Key {
  public static var rooms: DistributedReception.Key<Room> { "rooms" }
}
