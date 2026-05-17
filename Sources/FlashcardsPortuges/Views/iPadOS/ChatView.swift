import SwiftUI

/// iPadOS Chat tab. Single-pane chat with message list and bottom
/// input bar — uses the full iPad width. Shares ChatMessageBubble
/// and RichMessageText from Views/ (the only shared view primitives).
struct ChatView: View {
  @ObservedObject var store: DictionaryStore
  @StateObject private var chatStore = ChatStore()
  @StateObject private var viewModel: ChatViewModel
  @FocusState private var inputFocused: Bool

  init(store: DictionaryStore) {
    self.store = store
    let cs = ChatStore()
    _chatStore = StateObject(wrappedValue: cs)
    _viewModel = StateObject(wrappedValue: ChatViewModel(
      store: store,
      chatStore: cs
    ))
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        messageList
        inputBar
      }
      .navigationTitle("Sofia")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            chatStore.messages.removeAll()
          } label: {
            Image(systemName: "arrow.counterclockwise")
          }
          .disabled(chatStore.messages.isEmpty)
        }
      }
      .sheet(isPresented: $viewModel.showAddSheet) {
        addToDeckSheet
      }
    }
  }

  // MARK: - Message list

  @ViewBuilder
  private var messageList: some View {
    if chatStore.messages.isEmpty {
      ContentUnavailableView(
        "Chat with Sofia",
        systemImage: "bubble.left.and.bubble.right",
        description: Text(
          "Your Portuguese tutor. Ask questions, practice conversation, or get help with the app."
        )
      )
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(chatStore.messages) { message in
              iPadMessageBubble(message: message,
                onAddToDeck: { phrase in
                  viewModel.startAddToDeck(phrase: phrase)
                }
              )
              .id(message.id)
            }
            if viewModel.busy {
              HStack {
                ProgressView()
                  .padding(.leading)
                Spacer()
              }
            }
            if let error = viewModel.error {
              Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal)
            }
          }
          .padding()
        }
        .onChange(of: chatStore.messages.count) { _, _ in
          if let last = chatStore.messages.last {
            withAnimation {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
        }
      }
    }
  }

  // MARK: - Input bar

  @ViewBuilder
  private var inputBar: some View {
    HStack(spacing: 8) {
      TextField("Message Sofia…", text: $chatStore.input, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .focused($inputFocused)
        .lineLimit(1...5)
        .onSubmit { sendIfReady() }

      Button {
        sendIfReady()
      } label: {
        Image(systemName: "arrow.up.circle.fill")
          .font(.title2)
      }
      .disabled(
        chatStore.input.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty || viewModel.busy
      )
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.bar)
  }

  private func sendIfReady() {
    let trimmed = chatStore.input.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !trimmed.isEmpty, !viewModel.busy else { return }
    viewModel.send()
    inputFocused = false
  }

  // MARK: - Add to deck sheet

  @ViewBuilder
  private var addToDeckSheet: some View {
    NavigationStack {
      Form {
        Section("Portuguese") {
          Text(viewModel.addToDeckPhrase)
            .font(.body)
        }
        Section("English") {
          if viewModel.translatingPhrase {
            HStack {
              TextField("English", text: $viewModel.addToDeckEnglish)
              ProgressView().controlSize(.small)
            }
          } else {
            TextField("English", text: $viewModel.addToDeckEnglish)
          }
        }
      }
      .navigationTitle("Add to Deck")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            viewModel.showAddSheet = false
          }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("Add") {
            viewModel.confirmAddToDeck()
          }
        }
      }
    }
    .frame(minWidth: 420, idealWidth: 480)
  }
}

// MARK: - Message bubble (iPadOS-local — avoids batch-compilation
// visibility issue with shared Views/ChatMessageBubble.swift)

private struct iPadMessageBubble: View {
  let message: ChatMessage
  let onAddToDeck: (String) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Circle()
        .fill(message.role == .user ? Color.accentColor : .green)
        .frame(width: 28, height: 28)
        .overlay(
          Text(message.role == .user ? "Y" : "S")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
        )

      VStack(alignment: .leading, spacing: 4) {
        Text(message.role == .user ? "You" : "Sofia")
          .font(.caption.weight(.semibold))
        Text(message.content)
          .font(.body)
          .textSelection(.enabled)

        if let gen = message.generation {
          Text(String(
            format: "%.1f tok/s",
            gen.tokensPerSecond
          ))
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
      }
    }
    .padding(8)
    .background(
      message.role == .user
        ? Color.accentColor.opacity(0.08)
        : Color.green.opacity(0.08)
    )
    .cornerRadius(12)
  }
}
