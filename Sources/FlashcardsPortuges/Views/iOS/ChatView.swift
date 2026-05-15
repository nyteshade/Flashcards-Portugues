import SwiftUI

/// iOS-native Chat tab. ScrollView of `MessageBubble`s and an input
/// bar pinned to the bottom via `.safeAreaInset(.bottom)` so the
/// keyboard pushes it up naturally. New Chat is the leading nav-bar
/// button; settings gear is trailing. Add-to-deck (triggered from a
/// Portuguese-chip's + button inside an assistant message) opens a
/// medium-detent sheet with the Portuguese pre-filled and the LLM's
/// auto-translation streaming into an editable English field.
struct ChatView: View {
  @StateObject private var viewModel: ChatViewModel
  @ObservedObject var chatStore: ChatStore
  @Binding var showSettings: Bool
  @FocusState private var inputFocused: Bool

  init(store: DictionaryStore, chatStore: ChatStore, showSettings: Binding<Bool>) {
    self.chatStore = chatStore
    self._showSettings = showSettings
    _viewModel = StateObject(
      wrappedValue: ChatViewModel(store: store, chatStore: chatStore)
    )
  }

  var body: some View {
    NavigationStack {
      messageList
        .navigationTitle("Sofia")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .tabBar)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              chatStore.startNewSession()
            } label: {
              Image(systemName: "square.and.pencil")
            }
            .disabled(chatStore.messages.isEmpty && chatStore.input.isEmpty)
            .accessibilityLabel("New Chat")
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: {
              Image(systemName: "gearshape")
            }
          }
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { inputFocused = false }
          }
        }
        .safeAreaInset(edge: .bottom) {
          inputBar
        }
        .sheet(isPresented: $viewModel.showAddSheet) {
          AddToDeckSheet(viewModel: viewModel)
        }
    }
    .onChange(of: chatStore.focusToken) { _, _ in
      inputFocused = true
    }
  }

  // MARK: - Message list

  @ViewBuilder
  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if chatStore.messages.isEmpty { emptyState }

          ForEach(chatStore.messages) { msg in
            MessageBubble(message: msg, onAddToDeck: { phrase in
              viewModel.startAddToDeck(phrase: phrase)
            })
            .id(msg.id)
          }

          if viewModel.busy { thinkingRow }

          if let error = viewModel.error {
            Text(error)
              .font(.system(size: 13))
              .foregroundStyle(.red)
              .padding(.horizontal, 16)
          }

          Color.clear.frame(height: 1).id("bottomAnchor")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
      }
      .defaultScrollAnchor(.bottom)
      .onChange(of: chatStore.messages.count) { _, _ in
        withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
      }
      .onChange(of: viewModel.busy) { _, newValue in
        if newValue { withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) } }
      }
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer().frame(height: 40)
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
      Text("Ask Sofia about Portuguese")
        .font(.title3)
        .foregroundStyle(.secondary)
      Text("Translation nuances, grammar, verb tenses, cultural context — anything language-related.")
        .font(.callout)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
      Spacer().frame(height: 40)
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var thinkingRow: some View {
    HStack(spacing: 8) {
      ProgressView().controlSize(.small)
      Text("Sofia is thinking…")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 6)
  }

  // MARK: - Input bar

  @ViewBuilder
  private var inputBar: some View {
    HStack(alignment: .bottom, spacing: 8) {
      TextField("Message Sofia…", text: $chatStore.input, axis: .vertical)
        .lineLimit(1...5)
        .focused($inputFocused)
        .font(.system(size: 15))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
        )

      Button {
        viewModel.send()
      } label: {
        Image(systemName: "arrow.up.circle.fill")
          .font(.system(size: 32))
      }
      .buttonStyle(.plain)
      .foregroundStyle(
        viewModel.busy || chatStore.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? Color.secondary
          : Color.accentColor
      )
      .disabled(viewModel.busy ||
                chatStore.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.bar)
  }
}

// MARK: - Add to deck sheet

private struct AddToDeckSheet: View {
  @ObservedObject var viewModel: ChatViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Portuguese") {
          Text(viewModel.addToDeckPhrase)
            .italic()
            .font(.body)
        }
        Section("English translation") {
          HStack {
            TextField("Enter English translation…", text: $viewModel.addToDeckEnglish)
            if viewModel.translatingPhrase {
              ProgressView().controlSize(.small)
            }
          }
        }
      }
      .navigationTitle("Add to Deck")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") {
            viewModel.showAddSheet = false
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Add") {
            viewModel.confirmAddToDeck()
          }
          .disabled(viewModel.addToDeckEnglish
                      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .presentationDetents([.medium])
  }
}
