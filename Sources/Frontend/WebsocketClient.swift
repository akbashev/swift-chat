import HummingbirdWSCore
import HummingbirdWebSocket
import HummingbirdFoundation
import FoundationEssentials

public enum WebsocketClient {
  public static func configure(
    wsBuilder: HBWebSocketBuilder,
    api: Api
  ) {
    wsBuilder.addUpgrade()
    wsBuilder.add(middleware: HBLogRequestsMiddleware(.info))
    api.chat(WebsocketClient.chat(wsBuilder: wsBuilder))
  }
  
  private static func chat(
    wsBuilder: HBWebSocketBuilder
  ) -> AsyncStream<ChatConnection> {
    .init { continuation in
      wsBuilder.on(
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
          ws.initiateAutoPing(interval: .seconds(60))
          continuation.yield(
            .init(
              userId: userId,
              roomId: roomId,
              ws: ws
            )
          )
          return .ok
        }
      )
    }
  }
}
