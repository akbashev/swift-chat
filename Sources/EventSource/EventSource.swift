import Foundation
import PostgresNIO

/**
 This is a starting point to create some Event Sourcing with actors, thus very rudimentary.
 
 References:
 1. https://doc.akka.io/docs/akka/current/typed/persistence.html
 2. https://doc.akka.io/docs/akka/current/persistence.html
 3. https://learn.microsoft.com/en-us/dotnet/orleans/grains/grain-persistence/?pivots=orleans-7-0
 4. https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing
 */
// TODO: Will work for now, could be improved further
public protocol EventStore {
  associatedtype ID : Hashable
  
  func persistEvent<Event: Encodable>(_ event: Event, for id: ID) async throws
  func eventsFor<Event: Decodable>(_ persistenceId: ID) async throws -> [Event]
}

public protocol EventSourced: Actor {
  associatedtype Event: Codable & Sendable
  associatedtype ID : Hashable

  nonisolated var persistenceId: ID { get }
  func handleEvent(_ event: Event) async
}

public actor SomeActor: EventSourced {
  public nonisolated var persistenceId: String { "some_actor" }
  
  public enum Event: Codable & Sendable {
    case dataSaved(String)
  }
  
  var data: [String] = []
  let journal: Journal

  public func save(line: String) async {
    try? await self.journal.emit(Event.dataSaved(line), from: self)
  }
  
  public func get() -> [String] {
    self.data
  }
  
  public func handleEvent(_ event: Event) {
    switch event {
    case .dataSaved(let line):
      data.append(line)
    }
  }
  
  public init<S: EventStore>(store: S) async throws {
    self.journal = Journal(store: store)
    if let id = self.persistenceId as? S.ID {
      let events: [Event] = try await store.eventsFor(id)
      for event in events {
        self.handleEvent(event)
      }
    }
  }
}

actor Journal {
  let store: any EventStore

  func emit<Event: Codable & Sendable, Actor: EventSourced>(
    _ event: Event,
    from eventSourcedActor: Actor
  ) async throws {
    try await self.emit(event, from: eventSourcedActor, to: self.store)
  }
  
  private func emit<Event, Actor, Store>(
    _ event: Event,
    from actor: Actor,
    to store: Store
  ) async throws -> ()
  where Event: Codable & Sendable,
        Actor: EventSourced,
        Store: EventStore {
    guard let persistenceId = await actor.persistenceId as? Store.ID else { return }
    try await store.persistEvent(event, for: persistenceId)
    if let event = event as? Actor.Event {
      await actor.handleEvent(event)
    }
  }
  
  init(store: any EventStore) {
    self.store = store
  }
}

//import Distributed
//import DistributedCluster
//
//typealias DefaultDistributedActorSystem = ClusterSystem
//
//extension EventSourced where Self: DistributedActor {
//  public var journal: ClusterJournalPlugin {
//    get {
//       self.actorSystem.journal.host(name: "clusterJournal") { actorSystem in
//        ClusterJournalPlugin(actorSystem: actorSystem)
//      }
//    }
//  }
//}
