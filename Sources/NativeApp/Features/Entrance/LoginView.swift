import ComposableArchitecture
import Foundation
import SwiftUI

struct LoginView: View {

  @State var name: String = ""
  @State var password: String = ""
  let error: String?
  let login: (String, String) -> Void
  let switchToRegister: () -> Void

  var body: some View {
    VStack {
      if let error {
        Text(error)
          .foregroundStyle(Color.red)
          .font(.footnote)
      }
      TextField("Enter user name", text: $name)
        .disableAutoCapitalizationIfAvailable()
      SecureField("Enter password", text: $password)
      Button(
        action: {
          login(name, password)
        },
        label: {
          Text("Sign in")
        }
      ).disabled(name.count < 3 || password.count < 6)
      Button(
        action: {
          switchToRegister()
        },
        label: {
          Text("Create account")
        }
      )
      .buttonStyle(.borderless)
    }
    .padding()
    .interactiveDismissDisabled()
  }
}
