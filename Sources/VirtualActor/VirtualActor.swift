import Distributed
import DistributedCluster

public typealias VirtualID = String

// empty so far
public protocol VirtualActor: DistributedActor, Codable where ActorSystem == ClusterSystem {}
