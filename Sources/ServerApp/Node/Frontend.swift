import AuthCore
import Backend
import Distributed
import DistributedCluster
import Foundation
import Hummingbird
import HummingbirdWSCompression
import HummingbirdWebSocket
import Models
import OpenAPIHummingbird
import OpenAPIRuntime
import Persistence
import PostgresNIO
import ServiceLifecycle
import WebApp

struct Frontend: Service {

  let clusterSystem: ClusterSystem

  init(clusterSystem: ClusterSystem) {
    self.clusterSystem = clusterSystem
  }

  func run() async throws {
    let env = Environment()
    let authConfiguration = try AuthConfiguration(environment: env)
    let config = try PostgresConfig(
      host: self.clusterSystem.cluster.node.endpoint.host,
      environment: env
    ).generate()
    let persistence = try await Persistence(
      type: .postgres(config)
    )
    let participantConnectionManager = ParticipantRoomConnections(
      actorSystem: self.clusterSystem,
      logger: Logger(label: "ParticipantRoomConnections"),
      persistence: persistence
    )
    let router = Router(context: BasicAuthRequestContext<ParticipantModel>.self)
    let assetsURL = WebAppAssets.publicRoot
    router.add(middleware: FileMiddleware(assetsURL, searchForIndexHtml: false))
    let handler = Api(
      participantRoomConnections: participantConnectionManager,
      persistence: persistence
    )
    let authRouter = router.group("auth")
    authRouter.add(
      middleware: BasicParticipantAuthenticator(persistence: persistence)
    )
    authRouter.post("token") { _, context in
      let user = try context.requireIdentity()
      let token = try authConfiguration.jwtSigner.sign(subject: user.id.uuidString)
      return TokenResponse(accessToken: token, tokenType: "bearer", expiresIn: authConfiguration.jwtSigner.ttlSeconds)
    }

    let apiRouter = router.group()
    apiRouter.add(
      middleware: JWTAuthenticator(
        signer: authConfiguration.jwtSigner,
        persistence: persistence,
        exemptPaths: Set(["/participant", "/participant/login"])
      )
    )
    try handler.registerHandlers(on: apiRouter)
    WebAppRoutes(persistence: persistence, jwtSigner: authConfiguration.jwtSigner).register(on: router)
    // Separate router for websocket upgrade
    let wsRouter = Router(context: BasicWebSocketRequestContext.self)
    wsRouter.add(middleware: LogRequestsMiddleware(.debug))
    wsRouter.ws("chat/ws") { request, context in
      try await handler.shouldUpgrade(request: request, context: context)
    } onUpgrade: { inbound, outbound, context in
      try await handler.onUpgrade(inbound: inbound, outbound: outbound, context: context)
    }
    wsRouter.ws("app/chat/ws") { request, _ in
      guard
        let participantIdValue = request.uri.queryParameters["participant_id"].map(String.init),
        request.uri.queryParameters["room_id"] != nil,
        let cookieHeader = request.headers[.cookie],
        let token = parseCookies(cookieHeader)["auth_token"]
      else {
        return .dontUpgrade
      }
      do {
        let claims = try authConfiguration.jwtSigner.verify(token: token)
        guard claims.sub == participantIdValue else {
          return .dontUpgrade
        }
      } catch {
        return .dontUpgrade
      }
      return .upgrade([:])
    } onUpgrade: { inbound, outbound, context in
      let participantId = try context.request.uri.queryParameters.require("participant_id", as: UUID.self)
      let roomId = try context.request.uri.queryParameters.require("room_id", as: UUID.self)
      let request = ParticipantRoomConnections.Connection.RequestParameter(
        participantId: participantId,
        roomId: roomId
      )
      let outputStream = try await participantConnectionManager.addHTMXWSConnectionFor(
        request: request,
        inbound: inbound
      )
      for try await message in outputStream {
        guard let html = WebAppRoutes.renderMessageUpdate(message, currentUserId: participantId) else { continue }
        try await outbound.write(.text(html))
      }
    }
    var app = Application(
      router: router,
      server: .http1WebSocketUpgrade(
        webSocketRouter: wsRouter,
        configuration: .init(extensions: [.perMessageDeflate()])
      ),
      configuration: .init(
        address: .hostname(
          self.clusterSystem.cluster.node.host,
          port: 8080
        ),
        serverName: self.clusterSystem.name
      )
    )
    app.addServices(
      participantConnectionManager
    )
    try await app.run()
  }
}

private func parseCookies(_ raw: String) -> [String: String] {
  var values: [String: String] = [:]
  for part in raw.split(separator: ";") {
    let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    guard pair.count == 2 else { continue }
    values[pair[0]] = pair[1]
  }
  return values
}
