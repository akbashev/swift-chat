import SwiftUI
import ComposableArchitecture

@Reducer
public struct Entrance: Reducer {
  
  @Dependency(\.apiClient) var apiClient
  
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
    
    @Shared(.fileStorage(.user)) var user: UserResponse?

    var sheet: Entrance.State.Navigation.SheetRoute?
    var query: String = ""
    @Presents var room: Room.State?
    var rooms: [RoomResponse] = []
    var isLoading: Bool = false
      
    public init() {}
  }
  
  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case onAppear
    case openCreateRoom
    case selectRoom(RoomResponse)
    case createUser(String)
    case createRoom(String, String?)
    case searchRoom(String)
    case didCreateRoom(Result<RoomResponse, any Error>)
    case didCreateUser(Result<UserResponse, any Error>)
    case didSearchRoom(Result<[RoomResponse], any Error>)
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
        return .run { send in
          await send(
            .didCreateUser(
              Result {
                try await apiClient.createUser(name: userName)
              }
            )
          )
        }
      case .openCreateRoom:
        state.sheet = .createRoom
        return .none
      case .createRoom(let name, let description):
        return .run { send in
          await send(
            .didCreateRoom(
              Result {
                try await apiClient.createRoom(
                  name: name,
                  description: description
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
                try await apiClient.searchRoom(
                  query: query
                )
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

extension RoomResponse: Identifiable {}

extension URL {
  static let user = URL.documentsDirectory.appending(component: "user.json")
}
