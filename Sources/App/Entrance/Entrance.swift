import SwiftUI
import ComposableArchitecture
import API

@Reducer
public struct Entrance: Reducer {
  
  @Dependency(\.client) var client
  
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

extension URL {
  static let user = URL.documentsDirectory.appending(component: "user.json")
}

extension Entrance {
  enum MappingError: Swift.Error {
    case user
    case room
    case roomSearch
  }
}

extension UserPresentation {
  init(_ output: Operations.createUser.Output) throws {
    let payload = try output.ok.body.json
    guard let id = UUID(uuidString: payload.id) else {
      throw Entrance.MappingError.user
    }
    self.id = id
    self.name = payload.name
  }
}

extension RoomPresentation {
  init(_ output: Operations.createRoom.Output) throws {
    let payload = try output.ok.body.json
    try self.init(payload)
  }
}


extension RoomPresentation {
  init(_ response: Components.Schemas.RoomResponse) throws {
    guard
      let id = UUID(uuidString: response.id)
    else {
      throw Entrance.MappingError.room
    }
    self.id = id
    self.name = response.name
    self.description = response.description
  }
}
