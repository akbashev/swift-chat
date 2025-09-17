import ComposableArchitecture
import Foundation
import SwiftUI

// MARK: - Feature view

public struct EntranceView: View {
  @Bindable var store: StoreOf<Entrance>

  public init(store: StoreOf<Entrance>) {
    self.store = store
  }

  public var body: some View {
    ScrollView {
      LazyVStack {
        ForEach(store.rooms) { room in
          RoomItemView(
            name: room.name,
            description: room.description
          ) {
            store.send(.selectRoom(room))
          }
        }
      }
      .padding()
    }
    .searchable(text: $store.query)
    .overlay {
      if store.isLoading {
        ProgressView()
      }
    }
    .onAppear {
      store.send(.onAppear)
    }
    .sheet(
      item: $store.sheet
    ) { route in
      RouteView(
        route: route,
        send: { action in
          switch action {
          case .createUser(let name):
            store.send(.createUser(name))
          case let .createRoom(name, description):
            store.send(.createRoom(name, description))
          }
        }
      )
    }
    .navigationDestination(item: $store.scope(state: \.room, action: \.room)) { store in
      RoomView(store: store)
    }
    .toolbar {
      ToolbarItem(
        id: "addRoomButton",
        placement: .automatic,
        showsByDefault: true
      ) {
        Button(action: {
          store.send(.openCreateRoom, animation: .default)
        }) {
          Text(Image(systemName: "plus"))
            .font(.body)
            .foregroundColor(Color.primary)
        }
      }
    }
  }
}

struct RouteView: View {

  @Environment(\.dismiss) var dismiss

  enum Action {
    case createUser(name: String)
    case createRoom(name: String, description: String?)
  }

  let route: Entrance.State.Navigation.SheetRoute
  let send: (Action) -> Void

  var body: some View {
    NavigationStack {
      switch route {
      case .createUser:
        CreateUserView { userName in
          send(.createUser(name: userName))
        }
        .navigationTitle("Create user")
      case .createRoom:
        CreateRoomView { userName, description in
          send(.createRoom(name: userName, description: description))
        }
        .navigationTitle("Create room")
        .toolbar {
          ToolbarItem(
            placement: .cancellationAction
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
  }
}

struct RoomItemView: View {

  let name: String
  let description: String?
  let open: () -> Void

  var body: some View {
    VStack(alignment: .leading) {
      Text(name)
        .font(.headline)
      description.map {
        Text($0)
      }
      Divider()
    }
    .frame(maxWidth: .infinity)
    .onTapGesture {
      self.open()
    }
  }
}
