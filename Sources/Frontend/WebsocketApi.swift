import HummingbirdFoundation
import FoundationEssentials
import HummingbirdWebSocket

public enum WebsocketApi {
  
  public enum Event {
    public struct Info {
      public let userId: UUID
      public let roomId: UUID
      public let ws: HBWebSocket
    }
    case connect(Info)
    case close(Info)
  }
  
  public static func configure(
    builder: HBWebSocketBuilder
  ) -> AsyncStream<Event> {
    .init { continuation in
      builder.on(
        "/chat",
        shouldUpgrade: { request in
          guard request.uri.queryParameters["user_id"] != nil,
                request.uri.queryParameters["room_id"] != nil
          else {
            throw HBHTTPError(.badRequest)
          }
          return nil
        },
        onUpgrade: { request, ws -> HTTPResponseStatus in
          guard let userId: UUID = request.uri.queryParameters["user_id"].flatMap(UUID.init(uuidString:)),
                let roomId: UUID = request.uri.queryParameters["room_id"].flatMap(UUID.init(uuidString:)) else {
            try await ws.close()
            return .badRequest
          }
          let info = Event.Info(
            userId: userId,
            roomId: roomId,
            ws: ws
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

