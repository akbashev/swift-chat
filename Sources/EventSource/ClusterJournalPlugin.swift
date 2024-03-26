//import Distributed
//import DistributedCluster
//import Foundation
//
//// Here magic should happen
//public actor ClusterJournalPlugin {
//
//  private var store: EventStore
//  private var actorSystem: ClusterSystem!
//  private let encoder: JSONEncoder
//  
//  func emit<Event: Codable>(_ event: Event, from actor: any DistributedActor & EventSourced) async {
//    try await store.persistEvent(encoder.encode(event), for: id)
//    // what't the purpose of whenLocal?! 🤔
//    actor.whenLocal { 
//      $0.handleEvent(event)
//    }
//  }
//}
//
//extension ClusterJournalPlugin: _Plugin {
//    static let pluginKey: Key = "$clusterJournal"
//
//    public nonisolated var key: Key {
//        Self.pluginKey
//    }
//
//    public func start(_ system: ClusterSystem) async throws {
//        self.actorSystem = system
//    }
//
//    public func stop(_ system: ClusterSystem) async {
//        self.actorSystem = nil
//        for (_, (_, boss)) in self.singletons {
//            await boss.stop()
//        }
//    }
//}
//
//extension ClusterSystem {
//  public var journal: ClusterJournalPlugin {
//    let key = ClusterJournalPlugin.pluginKey
//    guard let journalPlugin = self.settings.plugins[key] else {
//      fatalError("No plugin found for key: [\(key)], installed plugins: \(self.settings.plugins)")
//    }
//    return journalPlugin
//  }
//}
