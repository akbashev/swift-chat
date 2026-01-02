import ComposableArchitecture
import SwiftUI

@Reducer
public struct Entrance: Reducer, Sendable {

  @Dependency(\.client) var client
  @Dependency(\.chatClient) var chatClient
  @Dependency(\.authClient) var authClient

  @ObservableState
  public struct State {

    enum Navigation: Equatable, Identifiable {
      enum SheetRoute: Equatable, Identifiable {
        case register
        case login
        case createRoom

        public var id: String {
          switch self {
          case .register: "register"
          case .login: "login"
          case .createRoom: "createRoom"
          }
        }
      }

      enum PopoverRoute: Equatable, Identifiable {
        case error(String)

        public var id: String {
          switch self {
          case .error(let description): description
          }
        }
      }

      case sheet(SheetRoute)
      case popover(PopoverRoute)

      var id: String {
        switch self {
        case .sheet(let route): "sheet_\(route.id)"
        case .popover(let route): "popover_\(route.id)"
        }
      }
    }

    @Shared(.fileStorage(.user)) var user: ParticipantPresentation?
    @Shared(.appStorage("authToken")) var authToken: String?

    @Presents var room: Room.State?

    var sheet: Entrance.State.Navigation.SheetRoute?
    var query: String = ""
    var rooms: [RoomPresentation] = []
    var isLoading: Bool = false
    var authError: String?

    public init() {}
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case onAppear
    case openCreateRoom
    case openRegister
    case openLogin
    case signOut
    case selectRoom(RoomPresentation)
    case register(String, String)
    case login(String, String)
    case createRoom(String, String?)
    case searchRoom(String)
    case didCreateRoom(Result<RoomPresentation, Error>)
    case didRegisterUser(Result<ParticipantPresentation, any Error>)
    case didAuthenticate(Result<AuthToken, any Error>)
    case didSearchRoom(Result<[RoomPresentation], any Error>)
    case room(PresentationAction<Room.Action>)
  }

  enum CancellationId: Hashable {
    case searchRoom
  }

  public var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .onAppear:
        if state.user == .none {
          state.sheet = .login
        }
        return .none
      case .selectRoom(let response):
        state.room = .init(user: state.user!, room: response)
        return .none
      case .openRegister:
        state.sheet = .register
        state.authError = nil
        return .none
      case .openLogin:
        state.sheet = .login
        state.authError = nil
        return .none
      case .register(let userName, let password):
        return .run { send in
          let registeredUser = await Result {
            let user = try await client.register(body: .json(.init(name: userName, password: password)))
            return try ParticipantPresentation(user)
          }
          await send(.didRegisterUser(registeredUser))
          guard case .success = registeredUser else {
            return
          }
          let tokenResult = await Result {
            try await authClient.token(userName, password)
          }
          await send(.didAuthenticate(tokenResult))
        }
      case .login(let userName, let password):
        return .run { send in
          let loggedInUser = await Result {
            let user = try await client.login(body: .json(.init(name: userName, password: password)))
            return try ParticipantPresentation(user)
          }
          await send(.didRegisterUser(loggedInUser))
          guard case .success = loggedInUser else {
            return
          }
          let tokenResult = await Result {
            try await authClient.token(userName, password)
          }
          await send(.didAuthenticate(tokenResult))
        }
      case .openCreateRoom:
        state.sheet = .createRoom
        return .none
      case .signOut:
        let room = state.room?.room
        let user = state.user
        state.$user.withLock { $0 = nil }
        state.$authToken.withLock { $0 = nil }
        state.room = nil
        state.rooms = []
        state.query = ""
        state.sheet = .login
        guard let room, let user else {
          return .none
        }
        return .run { _ in
          await self.chatClient.disconnect(
            user: user,
            from: room
          )
        }
      case .createRoom(let name, let description):
        return .run { send in
          await send(
            .didCreateRoom(
              Result {
                try await RoomPresentation(
                  client.createRoom(
                    body: .json(
                      .init(
                        name: name,
                        description: description
                      )
                    )
                  )
                )
              }
            )
          )
        }
      case .searchRoom(let query):
        state.isLoading = true
        return .run { send in
          await send(
            .didSearchRoom(
              Result {
                try await client.searchRoom(
                  query: .init(query: query)
                ).ok
                  .body
                  .json
                  .compactMap(RoomPresentation.init)
              }
            )
          )
        }
      case let .didRegisterUser(.success(user)):
        state.$user.withLock { $0 = user }
        state.sheet = .none
        state.authError = nil
        return .none
      case let .didRegisterUser(.failure(error)):
        state.authError = error.localizedDescription
        return .none
      case let .didAuthenticate(.success(token)):
        state.$authToken.withLock { $0 = token.accessToken }
        state.authError = nil
        return .none
      case let .didAuthenticate(.failure(error)):
        state.authError = error.localizedDescription
        return .none
      case let .didCreateRoom(.success(room)):
        state.isLoading = false
        state.room = .init(user: state.user!, room: room)
        state.sheet = .none
        return .none
      case .didCreateRoom(.failure):
        state.isLoading = false
        return .none
      case .didSearchRoom(.success(let rooms)):
        state.rooms = rooms
        state.isLoading = false
        return .none
      case .didSearchRoom(.failure):
        state.isLoading = false
        return .none
      case .binding(\.query):
        guard !state.query.isEmpty else {
          state.rooms = []
          return .none
        }
        let query = state.query
        state.isLoading = true
        return .run { send in
          try await withTaskCancellation(id: CancellationId.searchRoom, cancelInFlight: true) {
            try await Task.sleep(for: .seconds(0.5))
            await send(.searchRoom(query))
          }
        }
      case .room(.dismiss):
        guard
          let room = state.room?.room,
          let user = state.user
        else {
          return .none
        }
        return .run { send in
          await self.chatClient.disconnect(
            user: user,
            from: room
          )
        }
      case .binding(_),
        .room(_):
        return .none
      }
    }
    .ifLet(\.$room, action: \.room) {
      Room()
    }
  }

  public init() {}
}

extension URL {
  static let user = URL.documentsDirectory.appending(component: "swift-chat-user.json")
}
