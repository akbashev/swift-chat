import ComposableArchitecture
import Dependencies
import Foundation
import API


@Reducer
public struct Room {
  
  @Dependency(\.continuousClock) var clock
  @Dependency(\.client) var client
  
  public typealias ChatMessage = Components.Schemas.ChatMessage

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
    case connect
    case alert(PresentationAction<Alert>)
    case messageToSendAdded(Message)
    case receivedMessage(ChatMessage)
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
          state.connectivityState = .disconnected
          return .cancel(id: CancelId.connection)
        case .disconnected:
          state.connectivityState = .connecting
          let userId = state.user.id.uuidString
          let roomId = state.room.id.uuidString
          return .run { send in
            let response = try await client.getMessages(
              query: .init(
                user_id: userId,
                room_id: roomId
              ),
              headers: .init(
                accept: [
                  .init(
                    contentType: .application_jsonl
                  )
                ]
              )
            )
            let messageStream = try response.ok.body.application_jsonl.asDecodedJSONLines(
              of: Room.ChatMessage.self
            )
            await send(.updatedConnectivityState(.connected))
            try await withTaskCancellation(id: CancelId.connection) {
              try await withThrowingTaskGroup(of: Void.self) { group in
                for try await message in messageStream {
                  group.addTask {
                    await send(.receivedMessage(message))
                  }
                }
              }
              await send(.updatedConnectivityState(.disconnected))
            }
          }
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
          for message in messages {
            let chatMessage = ChatMessage(
              user: user,
              room: room,
              message: message
            )
            _ = try await self.client.sendMessage(body: .json(chatMessage))
          }
          await send(
            .didSend(.success(messages))
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
      case let .didSend(.failure(error)):
        state.isSending = false
        state.alert = AlertState {
          TextState(
            """
            Could not send socket message.
            Reason: \(error.localizedDescription). 
            Connect to the server first, and try again.
            """
          )
        }
        return .none
      case .updatedConnectivityState(let connectivityState):
        state.connectivityState = connectivityState
        return .none
      case .didSend:
        state.isSending = false
        state.receivedMessages.removeAll()
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
  init(_ message: Room.ChatMessage) throws {
    self.user = try .init(message.user)
    self.room = try .init(message.room)
    self.message = switch message.message {
    case .DisconnectMessage: 
        .disconnect
    case .JoinMessage: 
        .join
    case .LeaveMessage: 
        .leave
    case .TextMessage(let message):
        .message(message.content, at: message.timestamp)
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
}
