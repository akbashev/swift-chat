import Distributed
import DistributedCluster
import Plugins
import Models
import Store

public distributed actor User: Observable {
  
  public typealias ActorSystem = ClusterSystem
  
  private var state: State
  private lazy var observer: Observer<Output> = .init()
  
  // API
  distributed public func send(message: Message, to room: Room) async throws {
    switch message {
      case .join:
        try await self.join(room: room)
      case .message(let string):
        try await room.message(.message(string), from: self)
      case .leave:
        try self.check(room: room)
        try await self.leave(room: room)
      case .disconnect:
        try self.check(room: room)
        self.disconnect(room: room)
    }
  }
    
  // Room
  distributed func notify(_ message: Message, user: User, from room: Room) {
    Task {
      let userInfo = try await user.getUserInfo()
      try await self.observer.resolve(
        with: .success(
          .message(
            message,
            user: userInfo,
            room: room.getRoomInfo()
          )
        )
      )
    }
  }
  
  distributed func getUserInfo() -> UserInfo {
    self.state.info
  }
  
  distributed public func subscribe() async throws -> Output {
    try await self.observer.value
  }
  
  public init(
    actorSystem: ClusterSystem,
    userId: UserInfo.ID,
    store: Store
  ) async throws {
    self.actorSystem = actorSystem
    let userInfo = try await store.getUser(with: userId)
    self.state = .init(
      info: userInfo
    )
    await self.actorSystem.receptionist.checkIn(self, with: .users)
  }
  
  private func join(room: Room) async throws {
    try await room.message(.join, from: self)
    self.state.rooms.insert(room)
  }
  
  private func leave(room: Room) async throws {
    try await room.message(.leave, from: self)
    self.state.rooms.remove(room)
  }
  
  private func disconnect(room: Room) {
    Task {
      try await room.message(.disconnect, from: self)
    }
  }
  
  private func check(room: Room) throws {
    guard self.state.rooms.contains(room) else { throw User.Error.roomIsNotAvailable } // throw
  }
  
  deinit {
    let rooms = self.state.rooms
    Task {
      await withThrowingTaskGroup(of: Void.self) { group in
        for room in rooms {
          group.addTask {
            try await room.message(.disconnect, from: self)
          }
        }
      }
    }
  }
}

extension User {
  
  public enum Error: Swift.Error {
    case roomIsNotAvailable
  }
  
  public enum Output: Codable, Sendable {
    case message(Message, user: UserInfo, room: RoomInfo)
  }

  private struct State: Equatable {
    var rooms: Set<Room> = .init()
    let info: UserInfo
  }
}

extension DistributedReception.Key {
  public static var users: DistributedReception.Key<User> { "users" }
}
