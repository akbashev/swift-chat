import SwiftUI
import ComposableArchitecture

public struct Entrance: Reducer {
  
  @Dependency(\.userDefaults) var userDefaults
  @Dependency(\.apiClient) var apiClient
  
  public struct State: Equatable {
    
    @BindingState var sheet: Entrance.State.Navigation.SheetRoute?
    @BindingState var query: String = ""
    @PresentationState var room: Room.State?
    var rooms: [RoomResponse] = []
    var isLoading: Bool = false
    
    var showRoomView: Bool {
      self.user != .none
    }
    
    var user: UserResponse?
    
    public init() {
      @Dependency(\.userDefaults) var userDefaults
      if let data = userDefaults.dataForKey(.userInfo),
         let user = try? JSONDecoder().decode(UserResponse.self, from: data) {
        self.user = user
      } else {
        self.sheet = .createUser
      }
    }
  }
  
  public enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case onAppear
    case openCreateRoom
    case selectRoom(RoomResponse)
    case createUser(String)
    case createRoom(String, String?)
    case searchRoom(String)
    case didCreateRoom(TaskResult<RoomResponse>)
    case didCreateUser(TaskResult<UserResponse>)
    case didSearchRoom(TaskResult<[RoomResponse]>)
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
        return .none
      case .selectRoom(let response):
        state.room = .init(user: state.user!, room: response)
        return .none
      case .createUser(let userName):
        return .run { send in
          await send(
            .didCreateUser(
              TaskResult {
                try await apiClient.createUser(userName)
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
              TaskResult {
                try await apiClient.createRoom(name, description)
              }
            )
          )
        }
      case .searchRoom(let query):
        state.isLoading = true
        return .run { send in
          await send(
            .didSearchRoom(
              TaskResult {
                try await apiClient.searchRoom(query)
              }
            )
          )
        }
      case let .didCreateUser(.success(user)):
        state.user = user
        state.sheet = .none
        return .run { _ in
          try await userDefaults.setData(JSONEncoder().encode(user), .userInfo)
        }
      case let .didCreateUser(.failure(error)):
        return .none
      case let .didCreateRoom(.success(room)):
        state.isLoading = false
        state.room = .init(user: state.user!, room: room)
        state.sheet = .none
        return .none
      case let .didCreateRoom(.failure(error)):
        state.isLoading = false
        return .none
      case .didSearchRoom(let result):
        state.rooms = (try? result.value) ?? []
        state.isLoading = false
        return .none
      case .binding(\.$query):
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

extension Entrance.State {
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
}

extension RoomResponse: Identifiable {}
