import Hummingbird
import Foundation
import Backend
import Persistence
import DistributedCluster
import PostgresNIO
import ServiceLifecycle
import API
import OpenAPIHummingbird
import OpenAPIRuntime
import AsyncAlgorithms

struct ClientServerConnectionHandler: Service {
  
  typealias Value = Components.Schemas.ChatMessage
  
  let userRoomConnections: UserRoomConnections
  let heartbeatSequence = AsyncTimerSequence(
    interval: UserRoomConnections.heartbeatInterval,
    clock: .continuous
  )
  
  init(
    actorSystem: ClusterSystem,
    persistence: Persistence
  ) {
    self.userRoomConnections = .init(
      actorSystem: actorSystem,
      persistence: persistence
    )
  }

  func getStream(
    info: Operations.getMessages.Input
  ) async throws -> AsyncStream<Value> {
    let userId = info.headers.user_id
    let roomId = info.headers.room_id
    let (stream, continuation) = AsyncStream<Value>.makeStream()
    let inputStream = switch info.body {
    case .application_jsonl(let body):
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

  func run() async throws {
    await self.heartbeat()
  }

  private func heartbeat() async {
    for await _ in heartbeatSequence {
      await self.userRoomConnections.checkConnections()
    }
  }
}
