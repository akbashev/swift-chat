import SwiftUI
import ComposableArchitecture
import Foundation

// MARK: - Feature view

public struct EntranceView: View {
  let store: StoreOf<Entrance>
  
  public init(store: StoreOf<Entrance>) {
    self.store = store
  }
  
  struct ViewState: Equatable {
    @BindingViewState var userName: String
    @BindingViewState var roomName: String
    var isConnecting: Bool
    var showRoomView: Bool
  }
  
  public var body: some View {
    WithViewStore(
      self.store,
      observe: {
        ViewState(
          userName: $0.$userName,
          roomName: $0.$roomName,
          isConnecting: $0.isConnecting,
          showRoomView: $0.showRoomView
        )
      }
    ) { viewStore in
      VStack {
        switch viewStore.showRoomView {
          case false:
            TextField("Enter user name", text: viewStore.$userName)
            Button(
              action: {
                viewStore.send(.createUser)
              },
              label: {
                Text("Create")
              }
            ).disabled(viewStore.userName.count < 3)
          case true:
            TextField("Enter room name to connect", text: viewStore.$roomName)
            Button(
              action: {
                viewStore.send(.connectToRoom)
              },
              label: {
                Text("Create")
              }
            ).disabled(viewStore.isConnecting || viewStore.roomName.count < 3)
        }
      }
      .padding()
      .navigationDestination(
        store: self.store.scope(
          state: \.$room, action: { .room($0) }
        )
      ) { store in
        RoomView(store: store)
      }
    }
  }
}
