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
//    var logger = Logger(label: "WebSocketChat")
//    logger.logLevel = .trace
    // Separate router for websocket upgrade
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
          let userId: UUID = context.request.uri.queryParameters["user_id"]
            .flatMap(UUID.init(uuidSubtring:)),
          let roomId: UUID = context.request.uri.queryParameters["room_id"]
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

//extension WebsocketApi.WebSocket {
//  init(_ ws: WebSocketCl) {
//    self.close = { [weak ws] in
//      try await ws?.close()
//    }
//    self.write = { [weak ws] messages in
//      var data = ByteBuffer()
//      _ = try? data.writeJSONEncodable(messages)
//      _ = ws?.write(.binary(data))
//    }
//    self.read = .init { continuation in
//      /// Quickly checked and see *.map()* for AsyncSequence, but don't get a bit how to use it 🤔
//      Task {
//        for await message in ws.readStream() {
//          switch message {
//          case .text(let string):
//            continuation.yield(.text(string))
//          case .binary(var data):
//            guard let messages = try? data.readJSONDecodable(
//              [ChatResponse.Message].self,
//              length: data.readableBytes
//            ) else { break }
//            continuation.yield(.response(messages))
//          }
//        }
//      }
//    }
//  }
//}

extension UUID {
  init?(uuidSubtring: Substring) {
    self.init(uuidString: String(uuidSubtring))
  }
}
