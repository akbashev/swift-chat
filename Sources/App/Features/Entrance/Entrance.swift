import SwiftUI
import ComposableArchitecture
import API

@Reducer
public struct Entrance: Reducer {
  
  @Dependency(\.client) var client
  @Dependency(\.chatClient) var chatClient

  @ObservableState
  public struct State {
    
    enum Navigation: Equatable, Identifiable {
      enum SheetRoute: Equatable, Identifiable {
        case createUser
        case createRoom
        
        public var id: String {
          switch self {
          case .createUser: "createUser"
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
    
    @Shared(.fileStorage(.user)) var user: UserPresentation?

    @Presents var room: Room.State?

    var sheet: Entrance.State.Navigation.SheetRoute?
    var query: String = ""
    var rooms: [RoomPresentation] = []
    var isLoading: Bool = false
      
    public init() {}
  }
  
  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case onAppear
    case openCreateRoom
    case selectRoom(RoomPresentation)
    case createUser(String)
    case createRoom(String, String?)
    case searchRoom(String)
    case didCreateRoom(Result<RoomPresentation, Error>)
    case didCreateUser(Result<UserPresentation, any Error>)
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
          state.sheet = .createUser
        }
        return .none
      case .selectRoom(let response):
        state.room = .init(user: state.user!, room: response)
        return .none
      case .createUser(let userName):
        let client = self.client
        return .run { send in
          await send(
            .didCreateUser(
              Result {
                try await UserPresentation(
                  client.createUser(body: .json(.init(name: userName)))
                )
              }
            )
          )
        }
      case .openCreateRoom:
        state.sheet = .createRoom
        return .none
      case .createRoom(let name, let description):
        let client = self.client
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
        let client = self.client
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
      case let .didCreateUser(.success(user)):
        state.user = user
        state.sheet = .none
        return .none
      case .didCreateUser(.failure):
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
        let chatClient = self.chatClient
        return .run { send in
          await chatClient.disconnect(
            user: user,
            from: room
          )
        }
      case .binding(_),
          .room(_):
        return .none
      }
    }
    .ifLet(\.$room, action: /Action.room) {
      Room()
    }
  }
  
  public init() {}
}

extension URL {
  static let user = URL.documentsDirectory.appending(component: "user.json")
}
