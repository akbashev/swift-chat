import Hummingbird
import Foundation
import HummingbirdWebSocket
import HummingbirdWSCore
import Logging
import AsyncAlgorithms
import ServiceLifecycle

public enum WebsocketApi {
  
  public protocol ConnectionManager: Service {
    typealias OutputStream = AsyncChannel<WebSocketOutboundWriter.OutboundFrame>

    func add(
      info: Connection.Info,
      inbound: WebSocketInboundStream,
      outbound: WebSocketOutboundWriter
    ) async throws -> OutputStream
  }
  
  public struct Connection: Sendable {
    public struct Info: Hashable, Sendable {
      public let userId: UUID
      public let roomId: UUID
      
      public var description: String {
        "User \(self.userId.uuidString), Room \(self.roomId.uuidString)"
      }
    }
    
    public let info: Info
    public let inbound: WebSocketInboundStream
    public let outbound: ConnectionManager.OutputStream
    
    public init(
      info: Info,
      inbound: WebSocketInboundStream,
      outbound: ConnectionManager.OutputStream
    ) {
      self.info = info
      self.inbound = inbound
      self.outbound = outbound
    }
  }
  
  public static func configure(
    wsRouter: Router<BasicWebSocketRequestContext>,
    connectionManager: ConnectionManager
  ) {
    wsRouter.middlewares.add(LogRequestsMiddleware(.debug))
    wsRouter.ws(
      "/chat",
      shouldUpgrade: { request, context in
        guard
          request.uri.queryParameters["user_id"] != nil,
          request.uri.queryParameters["room_id"] != nil
        else {
          return .dontUpgrade
        }
        return .upgrade([:])
      },
      onUpgrade: { inbound, outbound, context in
        guard
          let userId: UUID = context.request.uri
            .queryParameters["user_id"]
            .flatMap(UUID.init(uuidSubtring:)),
          let roomId: UUID = context.request.uri
            .queryParameters["room_id"]
            .flatMap(UUID.init(uuidSubtring:))
        else {
          return
        }
        let outputStream = try await connectionManager.add(
          info: .init(userId: userId, roomId: roomId),
          inbound: inbound,
          outbound: outbound
        )
        for try await output in outputStream {
          try await outbound.write(output)
        }
      }
    )
  }
}

extension UUID {
  init?(uuidSubtring: Substring) {
    self.init(uuidString: String(uuidSubtring))
  }
}
