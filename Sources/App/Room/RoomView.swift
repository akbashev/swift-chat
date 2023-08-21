import SwiftUI
import ComposableArchitecture
import Foundation

// MARK: - Feature view

public struct RoomView: View {
  let store: StoreOf<Room>
  
  public init(store: StoreOf<Room>) {
    self.store = store
  }
  
  struct ViewState: Equatable {
    @BindingViewState var message: String
    @BindingViewState var isSending: Bool
    var userId: UUID
    var messages: [MessageResponse]
    var roomName: String
  }
  
  public var body: some View {
    WithViewStore(
      self.store,
      observe: {
        ViewState(
          message: $0.$message,
          isSending: $0.$isSending,
          userId: $0.user.id,
          messages: $0.receivedMessages,
          roomName: $0.room.name
        )
      }
    ) { viewStore in
      VStack {
        ScrollView {
          LazyVStack {
            ForEach(viewStore.messages) { response in
              switch response.message {
                case .join:
                  Text("\(response.user.name) joined the chat. 🎉🥳")
                case .disconnect:
                  Text("\(response.user.name) disconnected. 💤😴")
                case .leave:
                  Text("\(response.user.name) left the chat. 👋🥲")
                case .message(let message):
                  if response.user.id == viewStore.userId {
                    HStack {
                      Spacer()
                      Text(message)
                        .foregroundColor(.white)
                        .padding([.leading, .trailing], 6)
                        .padding([.top, .bottom], 4)
                        .background(
                          Capsule()
                            .strokeBorder(
                              Color.clear,
                              lineWidth: 0
                            )
                            .background(
                              Color.blue
                            )
                            .clipped()
                        )
                        .clipShape(Capsule())
                    }
                  } else {
                    HStack {
                      VStack(alignment: .leading, spacing: 2) {
                        Text(response.user.name + ":")
                          .font(.footnote)
                          .foregroundStyle(Color.secondary)
                        Text(message)
                          .foregroundColor(.white)
                          .padding([.leading, .trailing], 6)
                          .padding([.top, .bottom], 4)
                          .background(
                            Capsule()
                              .strokeBorder(
                                Color.clear,
                                lineWidth: 0
                              )
                              .background(
                                Color.green
                              )
                              .clipped()
                          )
                          .clipShape(Capsule())
                      }
                      Spacer()
                    }
                  }
              }
            }
          }
        }
        HStack {
          TextField(
            "Enter message",
            text: viewStore.$message
          )
          Spacer()
          Button {
            viewStore.send(.sendButtonTapped)
          } label: {
            Text("Send")
          }.disabled(viewStore.isSending)
        }
      }
      .navigationTitle(viewStore.roomName)
      .onAppear {
        viewStore.send(.onAppear)
      }
      .padding()
    }
  }
}

