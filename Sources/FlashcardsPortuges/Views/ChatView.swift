import SwiftUI

struct ChatView: View {
  @ObservedObject var store: DictionaryStore
  @ObservedObject private var translator = EuroLLMTranslator.shared

  @State private var messages: [ChatMessage] = []
  @State private var input: String = ""
  @State private var busy = false
  @State private var error: String?

  var body: some View {
    VStack(spacing: 0) {
      messageList

      Divider()

      inputBar
    }
  }

  // MARK: - Message list

  @ViewBuilder
  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if messages.isEmpty {
            emptyState
          }

          ForEach(messages) { msg in
            MessageBubble(message: msg)
              .id(msg.id)
          }

          if busy {
            thinkingRow
          }

          if let error = error {
            Text(error)
              .font(.callout)
              .foregroundStyle(.red)
              .padding(.horizontal, 16)
          }

          // Invisible anchor so we can scroll to bottom.
          Color.clear
            .frame(height: 1)
            .id("bottomAnchor")
        }
        .padding(16)
        .frame(maxWidth: .infinity)
      }
      .defaultScrollAnchor(.bottom)
      .onChange(of: messages.count) { _, _ in
        withAnimation {
          proxy.scrollTo("bottomAnchor", anchor: .bottom)
        }
      }
      .onChange(of: busy) { _, newValue in
        if newValue {
          withAnimation {
            proxy.scrollTo("bottomAnchor", anchor: .bottom)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer().frame(height: 60)
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
      Text("Ask EuroLLM about Portuguese")
        .font(.title3)
        .foregroundStyle(.secondary)
      Text("Translation nuances, grammar, verb tenses, cultural context — anything language-related.")
        .font(.callout)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
      Spacer().frame(height: 60)
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var thinkingRow: some View {
    HStack(spacing: 8) {
      ProgressView()
        .controlSize(.small)
      Text("Thinking…")
        .font(.callout)
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
      TextEditor(text: $input)
        .font(.body)
        .frame(minHeight: 36, maxHeight: 120)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
        )

      Button(action: send) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.system(size: 24))
      }
      .buttonStyle(.plain)
      .disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .help("Send (⌘↵)")
    }
    .padding(12)

    // Hidden button for Cmd+Return shortcut.
    ZStack {
      Button(action: send) { EmptyView() }
        .keyboardShortcut(.return, modifiers: .command)
        .opacity(0)
        .frame(width: 0, height: 0)
    }
    .accessibilityHidden(true)
  }

  // MARK: - Send

  private func send() {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !busy else { return }

    let userMessage = ChatMessage(role: .user, content: trimmed)
    messages.append(userMessage)
    input = ""
    error = nil
    busy = true

    // Build the full prompt including the new user message.
    let prompt = ChatService.buildPrompt(messages: messages)

    Task {
      defer {
        Task { @MainActor in busy = false }
      }
      do {
        let response = try await translator.chat(prompt: prompt)
        await MainActor.run {
          let assistantMessage = ChatMessage(role: .assistant, content: response)
          messages.append(assistantMessage)
        }
      } catch {
        await MainActor.run {
          self.error = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - Message bubble

struct MessageBubble: View {
  let message: ChatMessage

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      if message.role == .assistant {
        avatar
      } else {
        Spacer(minLength: 60)
      }

      VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
        Text(message.content)
          .font(.body)
          .textSelection(.enabled)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(
            RoundedRectangle(cornerRadius: 12)
              .fill(message.role == .user ? Color.accentColor : Color.gray.opacity(0.2))
          )
          .foregroundStyle(message.role == .user ? .white : .primary)
      }

      if message.role == .user {
        avatar
      } else {
        Spacer(minLength: 60)
      }
    }
  }

  @ViewBuilder
  private var avatar: some View {
    Image(systemName: message.role == .assistant ? "brain.head.profile" : "person.circle.fill")
      .font(.system(size: 22))
      .foregroundStyle(message.role == .assistant ? .indigo : .accentColor)
      .frame(width: 28, height: 28)
  }
}
