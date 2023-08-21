import SwiftUI
import App

@main
struct Main: SwiftUI.App {
  var body: some Scene {
    WindowGroup {
      NavigationStack {
        EntranceView(
          store: .init(
            initialState: .init(),
            reducer: {
              Entrance()
            }
          )
        )
      }
    }
  }
}
