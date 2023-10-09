import HummingbirdWSCore
import HummingbirdWebSocket
import HummingbirdFoundation
import FoundationEssentials

public actor WebsocketClient {
  
  private let wsBuilder: HBWebSocketBuilder
  private lazy var chat: AsyncStream<ChatConnection> = .init { continuation in
    self.wsBuilder.on(
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
            ws: .init(
              close: { [weak ws] code in
                try await ws?.close(code: code)
              },
              onClose: { [weak ws] callback in
                ws?.onClose(callback)
              },
              write: { [weak ws] data in
                try await ws?.write(data)
              },
              messages: ws.readStream
            )
          )
        )
        return .ok
      }
    )
  }
  
  public init(
    wsBuilder: HBWebSocketBuilder
  ) {
    wsBuilder.addUpgrade()
    wsBuilder.add(middleware: HBLogRequestsMiddleware(.info))
    self.wsBuilder = wsBuilder
  }
  
  public func configure(
    api: Api
  ) {
    Task { [weak self] in
      guard let self else { return }
      for await connection in await self.chat {
        api.handle(connection)
      }
    }
  }
}
