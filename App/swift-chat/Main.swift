import ComposableArchitecture
import NativeApp
import SwiftUI

@main
struct Main: SwiftUI.App {

  let store: StoreOf<Entrance> = .init(
    initialState: .init(),
    reducer: {
      Entrance()
    }
  )

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        EntranceView(
          store: store
        )
      }
    }
  }
}
