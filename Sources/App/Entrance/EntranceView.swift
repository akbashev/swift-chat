import SwiftUI
import ComposableArchitecture
import Foundation

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
        createUser: {
          store.send(.createUser($0))
        },
        createRoom: {
          store.send(.createRoom($0, $1))
        }
      )
    }
    /// Regular `navigationDestination(item:_)` haven't worked here.
    // TODO: Figure out why
    .navigationDestinationWrapper(
      item: $store.scope(state: \.room, action: \.room)
    ) { store in
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
            placement: .automatic,
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
  }
}

struct RoomItemView: View {
  
  let name: String
  let description: String?
  let open: () -> ()
  
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


extension View {
  @available(iOS, introduced: 16, deprecated: 17)
  @available(macOS, introduced: 13, deprecated: 14)
  @available(tvOS, introduced: 16, deprecated: 17)
  @available(watchOS, introduced: 9, deprecated: 10)
  @ViewBuilder
  func navigationDestinationWrapper<D: Hashable, C: View>(
    item: Binding<D?>,
    @ViewBuilder destination: @escaping (D) -> C
  ) -> some View {
    navigationDestination(isPresented: item.isPresented) {
      if let item = item.wrappedValue {
        destination(item)
      }
    }
  }
}


fileprivate extension Optional where Wrapped: Hashable {
  var isPresented: Bool {
    get { self != nil }
    set { if !newValue { self = nil } }
  }
}
