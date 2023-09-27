import Distributed
import DistributedCluster
import EventSource
import FoundationEssentials

public distributed actor Room {
  
  public typealias ActorSystem = ClusterSystem
  
  private var state: State
  private var eventSource: EventSource<MessageInfo>
  
  distributed func message(_ message: Message, from user: User) async throws -> MessageInfo {
    let messageInfo: MessageInfo = try await MessageInfo(
      createdAt: Date(),
      roomId: self.state.info.id,
      userId: user.getUserInfo().id,
      message: message
    )
    try await self.eventSource.save(messageInfo)
    self.state.messages.append(messageInfo)
    switch message {
      case .join:
        self.state.users.insert(user)
        // TODO: add logic to this messages
      case .message:
        try check(user: user)
      case .leave, .disconnect:
        try check(user: user)
        self.state.users.remove(user)
    }
    self.notifyOthersAbout(
      message: messageInfo,
      from: user
    )
    return messageInfo
  }
  
  distributed public func getRoomInfo() -> RoomInfo {
    self.state.info
  }
  
  distributed public func getMessages() -> [MessageInfo] {
    self.state.messages
  }
  
  public init(
    actorSystem: ClusterSystem,
    roomInfo: RoomInfo,
    eventSource: EventSource<MessageInfo>
  ) async throws {
    self.actorSystem = actorSystem
    let id = roomInfo.id.rawValue.uuidString.lowercased()
    let messages = try await eventSource
      .get()
//      .get(predicate: "id::text = \(id)")
      .filter { $0.roomId == roomInfo.id }
    self.state = .init(
      info: roomInfo,
      messages: messages
    )
    self.eventSource = eventSource
    await actorSystem
      .receptionist
      .checkIn(self, with: .rooms)
  }
  
  private func check(user: User) throws {
    guard self.state.users.contains(user) else { throw Room.Error.userIsMissing }
  }
  
  // non-structured
  private func notifyOthersAbout(message: MessageInfo, from user: User) {
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
