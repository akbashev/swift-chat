import ComposableArchitecture
import Foundation
import SwiftUI

// MARK: - Feature view

public struct RoomView: View {

  @Bindable var store: StoreOf<Room>

  public init(store: StoreOf<Room>) {
    self.store = store
  }

  public var body: some View {
    VStack(spacing: 0) {
      ScrollViewReader { reader in
        ScrollView {
          LazyVStack {
            ForEach(Array(store.receivedMessages.enumerated()), id: \.0) { (index, response) in
              Group {
                switch response.message {
                case .join:
                  Text("\(response.user.name) joined the chat. 🎉🥳")
                case .disconnect:
                  Text("\(response.user.name) disconnected. 💤😴")
                case .leave:
                  Text("\(response.user.name) left the chat. 👋🥲")
                case .message(let message, _) where response.user == store.user:
                  UserMessage(message: message)
                case .message(let message, _):
                  OtherUsersMessage(name: response.user.name, message: message)
                }
              }
              .id(response.id)
            }
            ForEach(
              Array(
                zip(
                  store.messagesToSendTexts.indices,
                  store.messagesToSendTexts
                )
              ),
              id: \.0
            ) { (_, text) in
              MessageToSend(message: text)
            }
          }
          .padding()
          .onChange(of: store.receivedMessages) { oldValue, messages in
            guard let last = messages.last else { return }
            withAnimation {
              reader.scrollTo(last.id, anchor: .top)
            }
          }
          .onChange(of: store.messagesToSend) { oldValue, messages in
            guard !messages.isEmpty else { return }
            withAnimation {
              reader.scrollTo(messages.count - 1, anchor: .top)
            }
          }
        }
      }
      Divider()
      MessageField(
        message: $store.message,
        isSending: store.isSending,
        send: { store.send(.sendButtonTapped) }
      )
    }
    .onAppear {
      store.send(.onAppear)
    }
    .onDisappear {
      store.send(.onDisappear)
    }
    .navigationTitle(store.room.name)
  }
}

struct UserMessage: View {

  let message: String

  var body: some View {
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
  }
}

struct OtherUsersMessage: View {

  let name: String
  let message: String

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(name + ":")
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

struct MessageToSend: View {

  let message: String

  var body: some View {
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

struct MessageField: View {

  @Binding var message: String
  let isSending: Bool
  let send: () -> Void

  var body: some View {
    HStack {
      TextField(
        "Enter message",
        text: $message
      )
      Spacer()
      Button {
        send()
      } label: {
        Text("Send")
      }.disabled(isSending)
    }
    .padding()
    .background(.regularMaterial)
  }
}
