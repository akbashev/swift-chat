import API
import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
public struct Room: Sendable {

  @Dependency(\.client) var client
  @Dependency(\.chatClient) var chatClient

  @ObservableState
  public struct State {

    let room: RoomPresentation
    let user: UserPresentation

    var alert: AlertState<Action.Alert>?
    var message: String = ""
    var isSending: Bool = false
    var connectivityState = ConnectivityState.disconnected
    var receivedMessages: [MessagePresentation] = []
    var messagesToSend: [Message] = []

    var messagesToSendTexts: [String] {
      self.messagesToSend
        .compactMap { message in
          switch message {
          case .message(let text, _): text
          default: .none
          }
        }
    }

    public init(
      user: UserPresentation,
      room: RoomPresentation,
      alert: AlertState<Action.Alert>? = nil,
      connectivityState: ConnectivityState = ConnectivityState.disconnected,
      messagesToSend: [Message] = [],
      receivedMessages: [MessagePresentation] = []
    ) {
      self.user = user
      self.room = room
      self.alert = alert
      self.connectivityState = connectivityState
      self.messagesToSend = messagesToSend
      self.receivedMessages = receivedMessages
    }
  }

  public enum ConnectivityState: String, Sendable {
    case connected
    case connecting
    case disconnected
  }

  public enum Action: BindableAction, Sendable {
    case binding(BindingAction<State>)
    case onAppear
    case onDisappear
    case connect
    case disconnect
    case reconnect
    case alert(PresentationAction<Alert>)
    case messageToSendAdded(Message)
    case receivedMessage(ChatClient.Message)
    case updatedConnectivityState(ConnectivityState)
    case sendButtonTapped
    case send([Message])
    case didSend(Result<Void, any Error>)

    public enum Alert: Equatable, Sendable {}
  }

  enum CancelId {
    case connection
  }

  public var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .onAppear:
        switch state.connectivityState {
        case .connected, .connecting:
          return .none
        case .disconnected:
          return .run { send in
            await send(.connect)
          }
        }
      case .onDisappear:
        switch state.connectivityState {
        case .connected, .connecting:
          return .run { send in
            await send(.disconnect)
          }
        case .disconnected:
          return .none
        }
      case .connect:
        state.connectivityState = .connecting
        let user = state.user
        let room = state.room
        return .run { send in
          // TODO: Handle errors, disconnection and etc. properly
          do {
            let messages = try await self.chatClient.connect(
              user: user,
              to: room
            )
            await send(.updatedConnectivityState(.connected))
            await withTaskCancellation(id: CancelId.connection) {
              try? await withThrowingTaskGroup(of: Void.self) { group in
                for try await message in messages {
                  group.addTask {
                    await send(.receivedMessage(message))
                  }
                }
              }
            }
            await send(.reconnect)
          } catch {
            await send(.reconnect)
          }
        }
      case .reconnect:
        state.connectivityState = .disconnected
        let user = state.user
        let room = state.room
        return .run { send in
          await self.chatClient.disconnect(
            user: user,
            from: room
          )
          try await Task.sleep(for: .seconds(5))
          await send(.connect)
        }
      case .disconnect:
        guard state.connectivityState != .disconnected else {
          return .none
        }
        let user = state.user
        let room = state.room
        return .run { send in
          await self.chatClient.disconnect(
            user: user,
            from: room
          )
          await send(.updatedConnectivityState(.disconnected))
        }
      case let .messageToSendAdded(message):
        state.messagesToSend.append(message)
        return .none
      case let .receivedMessage(message):
        guard
          let message = try? MessagePresentation(message)
        else {
          return .none
        }
        if message.user == state.user {
          state.messagesToSend.removeAll(where: { $0 == message.message })
        }
        state.receivedMessages.append(message)
        return .none
      case .send(let messages):
        state.isSending = true
        let user = state.user
        let room = state.room
        return .run { send in
          await send(
            .didSend(
              Result {
                for message in messages {
                  let chatMessage = ChatClient.Message(
                    user: user,
                    room: room,
                    message: message
                  )
                  _ = try await self.chatClient.send(
                    message: chatMessage,
                    from: user,
                    to: room
                  )
                }
              }
            )
          )
        }
      case .sendButtonTapped:
        guard !state.message.isEmpty else { return .none }
        let message = state.message
        state.message = ""
        state.messagesToSend.append(.message(message, at: Date()))
        let messagesToSend = state.messagesToSend
        return .run { send in
          await send(.send(messagesToSend))
        }
      case let .didSend(result):
        state.isSending = false
        switch result {
        case .failure(let error):
          state.alert = AlertState {
            TextState(
              """
              Could not send socket message.
              Reason: \(error.localizedDescription).
              Connect to the server first, and try again.
              """
            )
          }
        default:
          break
        }
        return .none
      case .updatedConnectivityState(let connectivityState):
        state.connectivityState = connectivityState
        return .none
      case .alert:
        return .none
      case .binding:
        return .none
      }
    }
    .ifLet(\.alert, action: \.alert)
  }

  public init() {}
}
