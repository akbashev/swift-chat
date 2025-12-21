import ComposableArchitecture
import Foundation
import SwiftUI

// MARK: - Register view
struct RegisterView: View {

  @State var name: String = ""
  let register: (String) -> Void

  var body: some View {
    VStack {
      TextField("Enter user name", text: $name)
      Button(
        action: {
          register(name)
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
