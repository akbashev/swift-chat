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
    var messagesToSend: [String]
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
          messagesToSend: $0.messagesToSend
            .compactMap { message -> String? in
              switch message {
              case .message(let text, _):
                return text
              default:
                return .none
              }
            },
          roomName: $0.room.name
        )
      }
    ) { viewStore in
      VStack(spacing: 0) {
        ScrollViewReader { reader in
          ScrollView {
            LazyVStack {
              ForEach(viewStore.messages) { response in
                Group {
                  switch response.message {
                  case .join:
                    Text("\(response.user.name) joined the chat. 🎉🥳")
                  case .disconnect:
                    Text("\(response.user.name) disconnected. 💤😴")
                  case .leave:
                    Text("\(response.user.name) left the chat. 👋🥲")
                  case .message(let message, let date) where response.user.id == viewStore.userId:
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
                  case .message(let message, let date):
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
                .id(response.id)
              }
              ForEach(
                Array(
                  zip(
                    viewStore.messagesToSend.indices,
                    viewStore.messagesToSend
                  )
                ),
                id: \.0
              ) { (_, message) in
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
                          Color.gray
                        )
                        .clipped()
                    )
                    .clipShape(Capsule())
                  ProgressView()
                }
              }
            }
            .padding()
            .onChange(of: viewStore.messages) { messages in
              guard let last = messages.last else { return }
              withAnimation {
                reader.scrollTo(last.id, anchor: .top)
              }
            }
            .onChange(of: viewStore.messagesToSend) { messages in
              guard !messages.isEmpty else { return }
              withAnimation {
                reader.scrollTo(messages.count - 1, anchor: .top)
              }
            }
          }
        }
        Divider()
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
        .padding()
        .background(.regularMaterial)
      }
      .onAppear {
        viewStore.send(.onAppear)
      }
      .navigationTitle(viewStore.roomName)
    }
  }
}

