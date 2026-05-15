import SwiftUI

// MARK: - Main view

struct ChatView: View {
  @StateObject private var viewModel: ChatViewModel
  @ObservedObject var chatStore: ChatStore

  @FocusState private var inputFocused: Bool

  init(store: DictionaryStore, chatStore: ChatStore) {
    self.chatStore = chatStore
    _viewModel = StateObject(
      wrappedValue: ChatViewModel(store: store, chatStore: chatStore)
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      chatHeader
      Divider()
      messageList
      Divider()
      inputBar
    }
    .onAppear { inputFocused = true }
    .onChange(of: chatStore.focusToken) { _, _ in
      // Another tab (e.g. Dictionary's "Chat about this" button)
      // pre-filled the input — pull focus back to the editor.
      inputFocused = true
    }
    .sheet(isPresented: $viewModel.showAddSheet) {
      addToDeckSheet
    }
  }

  // MARK: - Header

  @ViewBuilder
  private var chatHeader: some View {
    HStack {
      Spacer()
      Button {
        chatStore.startNewSession()
      } label: {
        Label("New Chat", systemImage: "square.and.pencil")
      }
      .buttonStyle(.borderless)
      .help("Clear the conversation and start fresh with Sofia")
      .disabled(chatStore.messages.isEmpty && chatStore.input.isEmpty)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
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
        .padding(16)
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
      Spacer().frame(height: 60)
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 40)).foregroundStyle(.secondary)
      Text("Ask Sofia about Portuguese")
        .font(.title3).foregroundStyle(.secondary)
      Text("Translation nuances, grammar, verb tenses, cultural context — anything language-related.")
        .font(.callout).foregroundStyle(.tertiary)
        .multilineTextAlignment(.center).frame(maxWidth: 360)
      Spacer().frame(height: 60)
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var thinkingRow: some View {
    HStack(spacing: 8) {
      ProgressView().controlSize(.small)
      Text("Sofia is thinking…")
        .font(.system(size: 14)).foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 4).padding(.vertical, 6)
  }

  // MARK: - Input bar

  @ViewBuilder
  private var inputBar: some View {
    HStack(alignment: .center, spacing: 8) {
      TextEditor(text: $chatStore.input)
        .font(.system(size: 15))
        .frame(minHeight: 36, maxHeight: 120)
        .fixedSize(horizontal: false, vertical: true)
        .focused($inputFocused)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .onKeyPress(keys: [.return], phases: .down) { keyPress in
          if keyPress.modifiers.contains(.shift) { return .ignored }
          send()
          return .handled
        }

      Button(action: send) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.system(size: 24))
      }
      .buttonStyle(.plain)
      .disabled(viewModel.busy || chatStore.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .help("Send (Enter)")
    }
    .padding(12)
  }

  /// Thin wrapper that delegates to the ViewModel and re-focuses the
  /// editor so the user can keep typing. Focus is a per-view concept
  /// (`@FocusState`), so it stays here rather than in the VM.
  private func send() {
    viewModel.send()
    inputFocused = true
  }

  // MARK: - Add to deck sheet

  @ViewBuilder
  private var addToDeckSheet: some View {
    VStack(spacing: 16) {
      Text("Add to Study Deck")
        .font(.headline)

      VStack(alignment: .leading, spacing: 6) {
        Text("Portuguese").font(.caption).foregroundStyle(.secondary)
        Text(viewModel.addToDeckPhrase)
          .font(.system(size: 15, weight: .medium))
          .italic()
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("English translation").font(.caption).foregroundStyle(.secondary)
        HStack(spacing: 6) {
          TextField("Enter English translation…", text: $viewModel.addToDeckEnglish)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 15))
          if viewModel.translatingPhrase {
            ProgressView()
              .controlSize(.small)
          }
        }
      }

      HStack(spacing: 12) {
        Button("Cancel") { viewModel.showAddSheet = false }
          .keyboardShortcut(.escape)
        Spacer()
        Button("Add to Deck") {
          viewModel.confirmAddToDeck()
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.addToDeckEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding()
    .frame(width: 380)
  }
}

// MessageBubble, RichMessageText, and the Portuguese-segment parser
// live in Views/ChatMessageBubble.swift so both platforms share them.
