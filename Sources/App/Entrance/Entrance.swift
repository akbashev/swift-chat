import SwiftUI
import ComposableArchitecture

public struct Entrance: Reducer {

  @Dependency(\.userDefaults) var userDefaults
  @Dependency(\.apiClient) var apiClient

  public struct State: Equatable {
  
    @BindingState var userName: String = ""
    @BindingState var roomName: String = ""
    @PresentationState var room: Room.State?
    var isConnecting: Bool = false
    
    var showRoomView: Bool {
      self.user != .none
    }
    
    var user: UserResponse?
    
    public init() {
      // TODO: add after work on database will be done
//      @Dependency(\.userDefaults) var userDefaults
//      if let data = userDefaults.dataForKey(.userInfo),
//         let user = try? JSONDecoder().decode(UserResponse.self, from: data) {
//        self.user = user
//      }
    }
  }
  
  public enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case createUser
    case didCreateUser(TaskResult<UserResponse>)
    case connectToRoom
    case didConnectToRoom(TaskResult<RoomResponse>)
    case room(PresentationAction<Room.Action>)
  }
  
  public var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
        case .createUser:
          let name = state.userName
          return .run { send in
            await send(
              .didCreateUser(
                TaskResult {
                  try await apiClient.createUser(name,  UUID())
                }
              )
            )
          }
        case let .didCreateUser(.success(user)):
          state.user = user
          return .none
          // TODO: add after work on database will be done
//          return .run { _ in
//            try await userDefaults.setData(JSONEncoder().encode(user), .userInfo)
//          }
        case let .didCreateUser(.failure(error)):
          return .none
        case .connectToRoom:
          let name = state.roomName
          state.isConnecting = true
          return .run { send in
            await send(
              .didConnectToRoom(
                TaskResult {
                  try await apiClient.connectToRoom(name)
                }
              )
            )
          }
        case let .didConnectToRoom(.success(room)):
          state.isConnecting = false
          state.room = .init(user: state.user!, room: room)
          return .none
        case let .didConnectToRoom(.failure(error)):
          state.isConnecting = false
          return .none
        case .binding(_):
          return .none
        case .room(_):
          return .none
      }
    }
    .ifLet(\.$room, action: /Action.room) {
      Room()
    }
  }
  
  public init() {}
}
