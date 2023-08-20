import SwiftUI
import ComposableArchitecture
import Dependencies

public struct WebSocket: Reducer {
  
  @Dependency(\.continuousClock) var clock
  @Dependency(\.webSocket) var webSocket
  @Dependency(\.apiClient) var apiClient

  public struct State: Equatable {
    
    @PresentationState var alert: AlertState<Action.Alert>?
    @BindingState var message: String = ""
    @BindingState var isSending: Bool = false
    
    var connectivityState = ConnectivityState.disconnected
    var messagesToSend: [Message] = []
    var receivedMessages: [Response] = []
    var userId = UUID()
    
    public enum ConnectivityState: String {
      case connected
      case connecting
      case disconnected
    }
    
    public enum Message: Sendable, Codable, Equatable {
      case join
      case message(String)
      case leave
      case disconnect
    }
    
    public struct Response: Identifiable, Equatable, Codable {
      public struct User: Codable, Equatable {
        let id: UUID
        let name: String
      }
      
      public struct Room: Codable, Equatable {
        let id: UUID
        let name: String
      }

      public var id: Date { self.createdAt }
      
      let createdAt: Date
      let user: User
      let room: Room?
      let message: Message
    }
    
    public init(
      alert: AlertState<Action.Alert>? = nil,
      connectivityState: ConnectivityState = ConnectivityState.disconnected,
      messagesToSend: [Message] = [],
      receivedMessages: [Response] = []
    ) {
      self.alert = alert
      self.connectivityState = connectivityState
      self.messagesToSend = messagesToSend
      self.receivedMessages = receivedMessages
    }
  }
  
  public init() {}
  
  public enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case onAppear
    case alert(PresentationAction<Alert>)
    case connect
    case messageToSendAdded(State.Message)
    case receivedSocketMessage(TaskResult<WebSocketClient.Message>)
    case sendButtonTapped
    case sendResponse(didSucceed: Bool)
    case webSocket(WebSocketClient.Action)
    
    public enum Alert: Equatable {}
  }
  
  public var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
        case .onAppear:
          let id = state.userId
          return .run { send in
            try await apiClient.createUser(id, String.random(length: 5))
            await send(.connect)
          }
        case .alert:
          return .none
          
        case .connect:
          switch state.connectivityState {
            case .connected, .connecting:
              state.connectivityState = .disconnected
              return .cancel(id: WebSocketClient.ID())
              
            case .disconnected:
              state.connectivityState = .connecting
              let userId = state.userId.uuidString
              return .run { send in
                let actions = await self.webSocket
                  .open(WebSocketClient.ID(), URL(string: "ws://localhost:8080/chat?room_id=35031C4D-5577-4F48-848A-74762194BF86&user_id=\(userId)")!, [])
                await withThrowingTaskGroup(of: Void.self) { group in
                  for await action in actions {
                    // NB: Can't call `await send` here outside of `group.addTask` due to task local
                    //     dependency mutation in `Effect.{task,run}`. Can maybe remove that explicit task
                    //     local mutation (and this `addTask`?) in a world with
                    //     `Effect(operation: .run { ... })`?
                    group.addTask { await send(.webSocket(action)) }
                    switch action {
                      case .didOpen:
                        group.addTask {
                          while !Task.isCancelled {
                            try await self.clock.sleep(for: .seconds(10))
                            try? await self.webSocket.sendPing(WebSocketClient.ID())
                          }
                        }
                        group.addTask {
                          for await result in try await self.webSocket.receive(WebSocketClient.ID()) {
                            await send(.receivedSocketMessage(result))
                          }
                        }
                      case .didClose:
                        return
                    }
                  }
                }
              }
              .cancellable(id: WebSocketClient.ID())
          }
          
        case let .messageToSendAdded(message):
          state.messagesToSend.append(message)
          return .none
          
        case let .receivedSocketMessage(.success(message)):
          if case let .data(data) = message,
             let messages = try? JSONDecoder().decode([State.Response].self, from: data) {
            state.receivedMessages.append(contentsOf: messages)
          }
          return .none
          
        case .receivedSocketMessage(.failure):
          return .none
          
        case .sendButtonTapped:
          state.messagesToSend.append(.message(state.message))
          state.message = ""
          let messagesToSend = state.messagesToSend
          state.isSending = true
          return .run { send in
            let data = try JSONEncoder().encode(messagesToSend)
            try await self.webSocket.send(WebSocketClient.ID(), .data(data))
            await send(.sendResponse(didSucceed: true))
          } catch: { _, send in
            await send(.sendResponse(didSucceed: false))
          }
          .cancellable(id: WebSocketClient.ID())
          
        case .sendResponse(didSucceed: false):
          state.isSending = false
          state.alert = AlertState {
            TextState(
              "Could not send socket message. Connect to the server first, and try again."
            )
          }
          return .none
          
        case .sendResponse(didSucceed: true):
          state.isSending = false
          state.messagesToSend = []
          return .none
          
        case .webSocket(.didClose):
          state.connectivityState = .disconnected
          return .cancel(id: WebSocketClient.ID())
          
        case .webSocket(.didOpen):
          state.connectivityState = .connected
          state.receivedMessages.removeAll()
          return .none
          
        case .binding:
          return .none
      }
    }
    .ifLet(\.$alert, action: /Action.alert)
  }
}

// MARK: - Feature view

public struct WebSocketView: View {
  let store: StoreOf<WebSocket>
  
  public init(store: StoreOf<WebSocket>) {
    self.store = store
  }
  
  struct ViewState: Equatable {
    @BindingViewState var message: String
    @BindingViewState var isSending: Bool
    var userId: UUID
    var messages: [WebSocket.State.Response]
  }
  
  public var body: some View {
    WithViewStore(
      self.store,
      observe: {
        ViewState(
          message: $0.$message,
          isSending: $0.$isSending,
          userId: $0.userId,
          messages: $0.receivedMessages
        )
      }
    ) { viewStore in
      VStack {
        ScrollView {
          LazyVStack {
            ForEach(viewStore.messages) { response in
              switch response.message {
                case .join:
                  Text("\(response.user.name) joined the chat. 🎉🥳")
                case .disconnect:
                  Text("\(response.user.name) disconnected. 💤😴")
                case .leave:
                  Text("\(response.user.name) left the chat. 👋🥲")
                case .message(let message):
                  if response.user.id == viewStore.userId {
                    HStack {
                      Spacer()
                      Text(message)
                    }
                  } else {
                    HStack {
                      Text("\(response.user.name): \(message)")
                      Spacer()
                    }
                  }
              }
            }
          }
        }
        HStack {
          TextField(
            "Enter message",
            text: viewStore.$message
          )
          Spacer()
          Button {
            viewStore.send(.sendButtonTapped)
          } label: {
            Text("Send")
          }.disabled(viewStore.isSending)
        }
      }
      .navigationTitle("Chat")
      .onAppear {
        viewStore.send(.onAppear)
      }
    }
  }
}

// MARK: - WebSocketClient

public struct WebSocketClient {
  struct ID: Hashable, @unchecked Sendable {
    let rawValue: AnyHashable
    
    init<RawValue: Hashable & Sendable>(_ rawValue: RawValue) {
      self.rawValue = rawValue
    }
    
    init() {
      struct RawValue: Hashable, Sendable {}
      self.rawValue = RawValue()
    }
  }
  
  public enum Action: Equatable {
    case didOpen(protocol: String?)
    case didClose(code: URLSessionWebSocketTask.CloseCode, reason: Data?)
  }
  
  public enum Message: Equatable {
    public struct Unknown: Error {}
    
    case data(Data)
    case string(String)
    
    public init(_ message: URLSessionWebSocketTask.Message) throws {
      switch message {
        case let .data(data): self = .data(data)
        case let .string(string): self = .string(string)
        @unknown default: throw Unknown()
      }
    }
  }
  
  var open: @Sendable (ID, URL, [String]) async -> AsyncStream<Action>
  var receive: @Sendable (ID) async throws -> AsyncStream<TaskResult<Message>>
  var send: @Sendable (ID, URLSessionWebSocketTask.Message) async throws -> Void
  var sendPing: @Sendable (ID) async throws -> Void
}

extension WebSocketClient: DependencyKey {
  public static var liveValue: Self {
    return Self(
      open: { await WebSocketActor.shared.open(id: $0, url: $1, protocols: $2) },
      receive: { try await WebSocketActor.shared.receive(id: $0) },
      send: { try await WebSocketActor.shared.send(id: $0, message: $1) },
      sendPing: { try await WebSocketActor.shared.sendPing(id: $0) }
    )
    
    final actor WebSocketActor: GlobalActor {
      final class Delegate: NSObject, URLSessionWebSocketDelegate {
        var continuation: AsyncStream<Action>.Continuation?
        
        func urlSession(
          _: URLSession,
          webSocketTask _: URLSessionWebSocketTask,
          didOpenWithProtocol protocol: String?
        ) {
          self.continuation?.yield(.didOpen(protocol: `protocol`))
        }
        
        func urlSession(
          _: URLSession,
          webSocketTask _: URLSessionWebSocketTask,
          didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
          reason: Data?
        ) {
          self.continuation?.yield(.didClose(code: closeCode, reason: reason))
          self.continuation?.finish()
        }
      }
      
      typealias Dependencies = (socket: URLSessionWebSocketTask, delegate: Delegate)
      
      static let shared = WebSocketActor()
      
      var dependencies: [ID: Dependencies] = [:]
      
      func open(id: ID, url: URL, protocols: [String]) -> AsyncStream<Action> {
        let delegate = Delegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let socket = session.webSocketTask(with: url, protocols: protocols)
        defer { socket.resume() }
        var continuation: AsyncStream<Action>.Continuation!
        let stream = AsyncStream<Action> {
          $0.onTermination = { _ in
            socket.cancel()
            Task { await self.removeDependencies(id: id) }
          }
          continuation = $0
        }
        delegate.continuation = continuation
        self.dependencies[id] = (socket, delegate)
        return stream
      }
      
      func close(
        id: ID, with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?
      ) async throws {
        defer { self.dependencies[id] = nil }
        try self.socket(id: id).cancel(with: closeCode, reason: reason)
      }
      
      func receive(id: ID) throws -> AsyncStream<TaskResult<Message>> {
        let socket = try self.socket(id: id)
        return AsyncStream { continuation in
          let task = Task {
            while !Task.isCancelled {
              continuation.yield(await TaskResult { try await Message(socket.receive()) })
            }
            continuation.finish()
          }
          continuation.onTermination = { _ in task.cancel() }
        }
      }
      
      func send(id: ID, message: URLSessionWebSocketTask.Message) async throws {
        try await self.socket(id: id).send(message)
      }
      
      func sendPing(id: ID) async throws {
        let socket = try self.socket(id: id)
        return try await withCheckedThrowingContinuation { continuation in
          socket.sendPing { error in
            if let error = error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume()
            }
          }
        }
      }
      
      private func socket(id: ID) throws -> URLSessionWebSocketTask {
        guard let dependencies = self.dependencies[id]?.socket else {
          struct Closed: Error {}
          throw Closed()
        }
        return dependencies
      }
      
      private func removeDependencies(id: ID) {
        self.dependencies[id] = nil
      }
    }
  }
  
  public static let testValue = Self(
    open: unimplemented("\(Self.self).open", placeholder: AsyncStream.never),
    receive: unimplemented("\(Self.self).receive"),
    send: unimplemented("\(Self.self).send"),
    sendPing: unimplemented("\(Self.self).sendPing")
  )
}

struct ApiClient {
  let createUser: (UUID, String) async throws -> ()
}

extension ApiClient: DependencyKey {
  public static var liveValue: Self {
    .init { uuid, name in
      struct Request: Encodable {
        let id: String
        let name: String
      }
      let data = try JSONEncoder().encode(Request(id: uuid.uuidString, name: name))
      var request = URLRequest(url: URL(string: "http://localhost:8080/user")!)
      request.httpMethod = "POST"
      request.httpBody = data
      _ = try await URLSession.shared.data(for: request)
    }
  }
}


extension DependencyValues {
  var webSocket: WebSocketClient {
    get { self[WebSocketClient.self] }
    set { self[WebSocketClient.self] = newValue }
  }
  
  var apiClient: ApiClient {
    get { self[ApiClient.self] }
    set { self[ApiClient.self] = newValue }
  }
}
        
extension String {
  static func random(length: Int) -> String {
      let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      var randomString = ""
      for _ in 0 ..< length {
          let randomIndex = Int(arc4random_uniform(UInt32(letters.count)))
          let letter = letters[letters.index(letters.startIndex, offsetBy: randomIndex)]
          randomString += String(letter)
      }
      return randomString
  }
}
