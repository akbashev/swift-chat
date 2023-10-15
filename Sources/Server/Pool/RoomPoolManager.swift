import Backend
import Distributed
import DistributedCluster

/**
 Not actually pool, I guess? Just started to write some custom pool and name sticks now.
 Not sure what is proper name.
 */
/** 
 Guess it's Erlang's simple one for one.
 Ok, why we need a manager on top of room pools? `Room` actors are dynamically created, but in order to distribute actors
 on different nodes—we need somehow know about those nodes. Every room node (see `Server.swift` and `RoomNode.swift`)
 creates a RoomPool and RoomPoolManager listens for them. And then you can get a room pool (round roubin or some order?)
 and spawn room there -> meaning spawning a room on different node.
 Actually still note sure about naming. **Check other frameworks and platforms on how it's managed there**.
 */
distributed actor RoomPoolManager: LifecycleWatch {

  enum Error: Swift.Error {
    case roomPoolUnavailable
  }
    
  private lazy var roomPools: Set<RoomPool> = .init()
  private var listingTask: Task<Void, Never>?
  private var localRoomPool: RoomPool?

  distributed public func get() async throws -> RoomPool {
    guard let roomPool = self.roomPools.randomElement() else {
      return await RoomPool(actorSystem: self.actorSystem)
    }
    return roomPool
  }
  
  func terminated(actor id: DistributedCluster.ActorID) async {
    guard let room = self.roomPools.first(where: { $0.id == id }) else { return }
    self.roomPools.remove(room)
  }
  
  private func findRoomPools() {
    guard self.listingTask == nil else {
      actorSystem.log.info("Already looking for room pools")
      return
    }
    
    self.listingTask = Task {
      for await roomPool in await actorSystem.receptionist.listing(of: .roomPools) {
        self.roomPools.insert(roomPool)
        self.watchTermination(of: roomPool)
      }
    }
  }
  
  public init(
    actorSystem: ClusterSystem
  ) {
    self.actorSystem = actorSystem
    self.findRoomPools()
  }
}
