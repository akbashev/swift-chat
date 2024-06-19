import ComposableArchitecture
import Dependencies
import Foundation
import API


@Reducer
public struct Room {
  
  @Dependency(\.continuousClock) var clock
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
  
  public enum ConnectivityState: String {
    case connected
    case connecting
    case disconnected
  }
  
  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case onAppear
    case onDisappear
    case connect
    case disconnect
    case alert(PresentationAction<Alert>)
    case messageToSendAdded(Message)
    case receivedMessage(ChatClient.Message)
    case updatedConnectivityState(ConnectivityState)
    case sendButtonTapped
    case send([Message])
    case didSend(Result<[Message], any Error>)
    
    public enum Alert: Equatable {}
  }
  
  enum CancelId {
    case connection
  }
  
  public var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .onAppear:
        return .run { send in
          await send(.connect)
        }
      case .connect:
        switch state.connectivityState {
        case .connected, .connecting:
          return .none
        case .disconnected:
          state.connectivityState = .connecting
          let user = state.user
          let room = state.room
          return .run { send in
            // Handle errors, disconnection and etc. properly
            do {
              let messages = try await self.chatClient.connect(
                user: user,
                to: room
              )
              await send(.updatedConnectivityState(.connected))
              await withTaskCancellation(id: CancelId.connection) {
                await withTaskGroup(of: Void.self) { group in
                  do {
                    for try await message in messages {
                      group.addTask {
                        await send(.receivedMessage(message))
                      }
                    }
                  } catch {
                    print(error)
                  }
                }
              }
            } catch {
              print(error)
            }
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
      case .disconnect:
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
        state.messagesToSend.removeAll(where: { $0 == message.message })
        state.receivedMessages.append(message)
        return .none
      case .send(let messages):
        state.isSending = true
        let user = state.user
        let room = state.room
        return .run { send in
          do {
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
              await send(
                .receivedMessage(chatMessage)
              )
            }
            await send(
              .didSend(.success(messages))
            )
          } catch {
            await send(
              .didSend(.failure(error))
            )
          }
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
    .ifLet(\.alert, action: /Action.alert)
  }
  
  public init() {}
}

struct ParseError: Swift.Error {}

extension MessagePresentation {
  init?(_ message: ChatClient.Message) throws {
    self.user = try .init(message.user)
    self.room = try .init(message.room)
    switch message.message {
    case .DisconnectMessage: 
      self.message = .disconnect
    case .JoinMessage:
      self.message = .join
    case .LeaveMessage:
      self.message = .leave
    case .TextMessage(let message):
      self.message = .message(message.content, at: message.timestamp)
    case .HeartbeatMessage:
      return nil
    }
  }
}

extension Components.Schemas.ChatMessage {
  init(
    user: UserPresentation,
    room: RoomPresentation,
    message: Message
  ) {
    let user = Components.Schemas.UserResponse(user)
    let room = Components.Schemas.RoomResponse(room)
    let message: Components.Schemas.ChatMessage.messagePayload = switch message {
    case .disconnect:
        .DisconnectMessage(.init(_type: .disconnect))
    case .join:
        .JoinMessage(.init(_type: .join))
    case .leave:
        .LeaveMessage(.init(_type: .leave))
    case .message(let message, let date):
        .TextMessage(.init(_type: .message, content: message, timestamp: date))
    }
    self.init(
      user: user,
      room: room,
      message: message
    )
  }
  
  init(
    user: UserPresentation,
    room: RoomPresentation,
    message: Components.Schemas.HeartbeatMessage
  ) {
    let user = Components.Schemas.UserResponse(user)
    let room = Components.Schemas.RoomResponse(room)
    self.init(
      user: user,
      room: room,
      message: .HeartbeatMessage(message)
    )
  }
}
