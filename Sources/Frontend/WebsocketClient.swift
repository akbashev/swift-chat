import HummingbirdWSCore
import HummingbirdWebSocket
import HummingbirdFoundation
import FoundationEssentials

class WebsocketClient {
  
  private let ws: HBWebSocketBuilder
  
  func configure(
    api: Api
  ) {
    api.chat(chat())
  }
  
  func chat() -> AsyncStream<ChatConnection> {
    .init { continuation in
      self.ws.on(
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
  
  init(
    ws: HBWebSocketBuilder
  ) {
    self.ws = ws
    self.ws.addUpgrade()
    self.ws.add(middleware: HBLogRequestsMiddleware(.info))
  }
}
