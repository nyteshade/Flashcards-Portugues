import SwiftUI

struct ChatView: View {
  @ObservedObject var store: DictionaryStore
  @ObservedObject private var translator = EuroLLMTranslator.shared
  @ObservedObject private var tracker = ActivityTracker.shared

  @State private var messages: [ChatMessage] = []
  @State private var input: String = ""
  @State private var busy = false
  @State private var error: String?

  @FocusState private var inputFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      messageList

      Divider()

      inputBar
    }
    .onAppear { inputFocused = true }
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
              .font(.system(size: 13))
              .foregroundStyle(.red)
              .padding(.horizontal, 16)
          }

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
      Text("Ask Sofia about Portuguese")
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
    HStack(alignment: .center, spacing: 8) {
      TextEditor(text: $input)
        .font(.system(size: 15))
        .frame(minHeight: 36, maxHeight: 120)
        .fixedSize(horizontal: false, vertical: true)
        .focused($inputFocused)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .onKeyPress(keys: [.return], phases: .down) { keyPress in
          if keyPress.modifiers.contains(.shift) {
            return .ignored
          }
          send()
          return .handled
        }

      Button(action: send) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.system(size: 24))
      }
      .buttonStyle(.plain)
      .disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .help("Send (Enter)")
    }
    .padding(12)
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
    inputFocused = true

    let summary = tracker.contextualSummary()
    let prompt = ChatService.buildPrompt(messages: messages, activitySummary: summary)

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
        if message.role == .assistant {
          assistantBody
        } else {
          Text(message.content)
            .font(.system(size: 15))
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
              RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor)
            )
            .foregroundStyle(.white)
        }
      }

      if message.role == .user {
        avatar
      } else {
        Spacer(minLength: 60)
      }
    }
  }

  // MARK: - Assistant body with Portuguese audio buttons

  @ViewBuilder
  private var assistantBody: some View {
    // Split into paragraphs and detect Portuguese segments.
    let paragraphs = message.content
      .components(separatedBy: "\n")
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

    if paragraphs.isEmpty {
      Text(message.content)
        .font(.system(size: 15))
        .textSelection(.enabled)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    } else {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
          if para.looksPortuguese {
            portugueseSegment(para)
          } else {
            Text(para)
              .font(.system(size: 15))
              .textSelection(.enabled)
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.gray.opacity(0.2))
      )
    }
  }

  @ViewBuilder
  private func portugueseSegment(_ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Text(text)
        .font(.system(size: 15))
        .italic()
        .foregroundStyle(.primary)
        .textSelection(.enabled)

      Button {
        SpeechService.speak(text, language: .portuguese)
      } label: {
        Image(systemName: "speaker.wave.2")
          .font(.system(size: 12))
          .foregroundColor(.accentColor)
      }
      .buttonStyle(.plain)
      .help("Pronounce (European Portuguese)")
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

// MARK: - Portuguese detection

extension String {
  /// Heuristic: does this text contain Portuguese-specific diacritics?
  fileprivate var looksPortuguese: Bool {
    let ptChars: Set<Character> = [
      "ã", "õ", "ç", "â", "ê", "ô",
      "á", "é", "í", "ó", "ú",
      "à", "è", "ì", "ò", "ù",
      "ü"
    ]
    // Must have at least one Portuguese-specific character and be
    // more than just a single accented word (to avoid false
    // positives on stray characters).
    let hasDiacritic = contains { ptChars.contains($0) }
    let wordCount = split(separator: " ").count
    return hasDiacritic && wordCount >= 2
  }
}
