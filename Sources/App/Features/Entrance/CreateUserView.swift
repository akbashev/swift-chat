import ComposableArchitecture
import Foundation
import SwiftUI

// MARK: - Create room view
struct CreateUserView: View {

  @State var name: String = ""
  let create: (String) -> Void

  var body: some View {
    VStack {
      TextField("Enter user name", text: $name)
      Button(
        action: {
          create(name)
        },
        label: {
          Text("Create")
        }
      ).disabled(name.count < 3)
    }
    .padding()
    .interactiveDismissDisabled()
  }
}
