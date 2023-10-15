import HummingbirdFoundation
import FoundationEssentials
import HummingbirdWebSocket
import HummingbirdWSCore

public enum WebsocketApi {
  
  public enum Event {
    public struct Info {
      public let userId: UUID
      public let roomId: UUID
      public let ws: WebSocket
    }
    case connect(Info)
    case close(Info)
  }
  
  public struct WebSocket {
    public enum Message {
      case text(String)
      case response([ChatResponse.Message])
    }
    public let write: ([ChatResponse]) -> ()
    public let close: () async throws -> ()
    public let read: AsyncStream<Message>
  }
  
  /**
   Think there is no back pressure here, but don't wanna invent a wheel and seems like we can just wait a bit to improve:
   https://github.com/apple/swift-evolution/blob/main/proposals/0406-async-stream-backpressure.md
  */
  public static func configure(
    builder: HBWebSocketBuilder
  ) -> AsyncStream<Event> {
    .init { continuation in
      builder.on(
        "/chat",
        shouldUpgrade: { request in
          guard
            request.uri.queryParameters["user_id"] != nil,
            request.uri.queryParameters["room_id"] != nil
          else {
            throw HBHTTPError(.badRequest)
          }
          return nil
        },
        onUpgrade: { request, ws -> HTTPResponseStatus in
          guard
            let userId: UUID = request.uri.queryParameters["user_id"]
              .flatMap(UUID.init(uuidString:)),
            let roomId: UUID = request.uri.queryParameters["room_id"]
              .flatMap(UUID.init(uuidString:))
          else {
            try await ws.close()
            return .badRequest
          }
          let info = Event.Info(
            userId: userId,
            roomId: roomId,
            ws: .init(ws)
          )
          ws.initiateAutoPing(interval: .seconds(60))
          ws.onClose { _ in
            continuation.yield(.close(info))
          }
          continuation.yield(.connect(info))
          return .ok
        }
      )
    }
  }
}

extension WebsocketApi.WebSocket {
  init(_ ws: HBWebSocket) {
    self.close = { [weak ws] in
      try await ws?.close()
    }
    self.write = { [weak ws] messages in
      var data = ByteBuffer()
      _ = try? data.writeJSONEncodable(messages)
      _ = ws?.write(.binary(data))
    }
    self.read = .init { continuation in
      /// Quickly checked and see *.map()* for AsyncSequence, but don't get a bit how to use it 🤔
      Task {
        for await message in ws.readStream() {
          switch message {
          case .text(let string):
            continuation.yield(.text(string))
          case .binary(var data):
            guard let messages = try? data.readJSONDecodable(
              [ChatResponse.Message].self,
              length: data.readableBytes
            ) else { break }
            continuation.yield(.response(messages))
          }
        }
      }
    }
  }
}
