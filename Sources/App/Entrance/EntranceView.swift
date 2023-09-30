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
    @BindingViewState var sheet: Entrance.State.Navigation.SheetRoute?
    @BindingViewState var query: String
    var rooms: [RoomResponse]
    var isLoading: Bool
  }
  
  public var body: some View {
    WithViewStore(
      self.store,
      observe: {
        ViewState(
          sheet: $0.$sheet,
          query: $0.$query,
          rooms: $0.rooms,
          isLoading: $0.isLoading
        )
      }
    ) { viewStore in
      ScrollView {
        LazyVStack {
          ForEach(viewStore.rooms) { room in
            VStack(alignment: .leading) {
              Text(room.name)
                .font(.headline)
              room.description.map {
                Text($0)
              }
              Divider()
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
              viewStore.send(.selectRoom(room))
            }
          }
        }
        .padding()
      }
      .searchable(text: viewStore.$query)
      .overlay {
        if viewStore.isLoading {
          ProgressView()
        }
      }
      .onAppear {
        viewStore.send(.onAppear)
      }
      .sheet(
        item: viewStore.$sheet
      ) { route in
        RouteView(
          route: route,
          createUser: {
            viewStore.send(.createUser($0))
          },
          createRoom: {
            viewStore.send(.createRoom($0, $1))
          }
        )
      }
      .navigationDestination(
        store: self.store.scope(
          state: \.$room, action: { .room($0) }
        )
      ) { store in
        RoomView(store: store)
      }
      .toolbar {
        ToolbarItem(
          id: "addRoomButton",
          placement: .navigationBarTrailing,
          showsByDefault: true
        ) {
          Button(action: {
            viewStore.send(.openCreateRoom, animation: .default)
          }) {
            Text(Image(systemName: "plus"))
              .font(.body)
              .foregroundColor(Color.primary)
          }
        }
      }
    }
  }
}

struct RouteView: View {
  
  @Environment(\.dismiss) var dismiss
  
  let route: Entrance.State.Navigation.SheetRoute
  let createUser: (String) -> ()
  let createRoom: (String, String?) -> ()
  
  var body: some View {
    NavigationView {
      switch route {
      case .createUser:
        CreateUserView { userName in
          createUser(userName)
        }
        .navigationTitle("Create user")
      case .createRoom:
        CreateRoomView { userName, description in
          createRoom(userName, description)
        }
        .navigationTitle("Create room")
        .toolbar {
          ToolbarItem(
            id: "navigationBarBackButton",
            placement: .navigationBarLeading,
            showsByDefault: true
          ) {
            Button(action: {
              withAnimation(.spring()) {
                self.dismiss()
              }
            }) {
              Text(Image(systemName: "xmark"))
                .font(.body)
                .foregroundColor(Color.primary)
            }
          }
        }
      }
    }
    .navigationBarTitleDisplayMode(.large)
    .navigationViewStyle(.stack)
  }
}
