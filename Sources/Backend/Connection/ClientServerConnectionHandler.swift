import AsyncAlgorithms
import DistributedCluster
import Foundation
import Hummingbird
import Models
import OpenAPIHummingbird
import OpenAPIRuntime
import Persistence
import PostgresNIO
import ServiceLifecycle

public struct ClientServerConnectionHandler: Service {

  typealias Value = ChatMessage

  let userRoomConnections: UserRoomConnections
  let heartbeatSequence = AsyncTimerSequence(
    interval: UserRoomConnections.heartbeatInterval,
    clock: .continuous
  )

  public init(
    actorSystem: ClusterSystem,
    persistence: Persistence
  ) {
    self.userRoomConnections = .init(
      actorSystem: actorSystem,
      persistence: persistence
    )
  }

  func getStream(
    info: Operations.GetMessages.Input
  ) async throws -> AsyncStream<Value> {
    let userId = info.headers.userId
    let roomId = info.headers.roomId
    let (stream, continuation) = AsyncStream<Value>.makeStream()
    let inputStream =
      switch info.body {
      case .applicationJsonl(let body):
        body.asDecodedJSONLines(
          of: Value.self
        )
      }
    try await self.userRoomConnections.addConnectionFor(
      userId: userId,
      roomId: roomId,
      inputStream: inputStream,
      continuation: continuation
    )
    return stream
  }

  public func run() async throws {
    await self.heartbeat()
  }

  private func heartbeat() async {
    for await _ in heartbeatSequence {
      await self.userRoomConnections.checkConnections()
    }
  }
}
