import Distributed
import DistributedCluster

public typealias VirtualID = String

// empty so far
public protocol VirtualActor: DistributedActor, Codable where ActorSystem == ClusterSystem {}

extension ActorMetadataKeys {
  public var virtualID: ActorMetadataKey<VirtualID> { "$virtualID" }
}
