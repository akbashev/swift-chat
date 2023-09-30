import ComposableArchitecture
import Dependencies
import Foundation

public struct Room: Reducer {
  
  @Dependency(\.continuousClock) var clock
  @Dependency(\.webSocket) var webSocket

  public struct State: Equatable {
    
    @PresentationState var alert: AlertState<Action.Alert>?
    @BindingState var message: String = ""
    @BindingState var isSending: Bool = false
    
    let room: RoomResponse
    let user: UserResponse
    
    var connectivityState = ConnectivityState.disconnected
    var messagesToSend: [Message] = []
    var receivedMessages: [MessageResponse] = []
    
    public enum ConnectivityState: String {
      case connected
      case connecting
      case disconnected
    }
    
    public init(
      user: UserResponse,
      room: RoomResponse,
      alert: AlertState<Action.Alert>? = nil,
      connectivityState: ConnectivityState = ConnectivityState.disconnected,
      messagesToSend: [Message] = [],
      receivedMessages: [MessageResponse] = []
    ) {
      self.user = user
      self.room = room
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
    case messageToSendAdded(Message)
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
          return .run { send in
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
              let userId = state.user.id
              let roomId = state.room.id
              return .run { send in
                let actions = await self.webSocket
                  .open(WebSocketClient.ID(), URL(string: "ws://localhost:8080/chat?room_id=\(roomId)&user_id=\(userId)")!, [])
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
                            try await self.webSocket.sendPing(WebSocketClient.ID())
                          }
                        }
                        group.addTask {
                          for await result in try await self.webSocket.receive(WebSocketClient.ID()) {
                            await send(.receivedSocketMessage(result))
                          }
                        }
                      case .didClose:
                        print("didClose")
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
             let messages = try? JSONDecoder().decode([MessageResponse].self, from: data) {
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
