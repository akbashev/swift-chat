import SwiftUI
import App

@main
struct Main: SwiftUI.App {
  var body: some Scene {
    WindowGroup {
      WebSocketView(
        store: .init(
          initialState: .init(),
          reducer: {
            WebSocket()
          }
        )
      )
    }
  }
}
