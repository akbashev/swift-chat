import ComposableArchitecture
import Foundation
import SwiftUI

// MARK: - Create room view
struct CreateRoomView: View {

  @State var name: String = ""
  @State var description: String = ""
  let create: (String, String?) -> Void

  var body: some View {
    VStack {
      TextField("Enter room name", text: $name)
      TextField("Enter room description", text: $description)
      Button(
        action: {
          create(name, description.isEmpty ? .none : description)
        },
        label: {
          Text("Create")
        }
      ).disabled(name.count < 3)
    }
    .padding()
  }
}
