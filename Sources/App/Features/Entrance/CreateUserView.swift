import SwiftUI
import ComposableArchitecture
import Foundation

// MARK: - Create room view
struct CreateUserView: View {

  @State var name: String = ""
  let create: (String) -> ()
  
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
