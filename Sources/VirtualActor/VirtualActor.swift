import Distributed
import DistributedCluster

public typealias VirtualID = String

// empty so far
public protocol VirtualActor: DistributedActor, Codable, Sendable where ActorSystem == ClusterSystem {}
public protocol VirtualActorDependency: Codable & Sendable {}
public struct None: VirtualActorDependency {}
