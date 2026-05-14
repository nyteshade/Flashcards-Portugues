import Foundation

/// Owns the Chat tab's mutable state and side-effecting actions so the
/// view stays a thin SwiftUI binding layer. Holds references to the
/// shared stores it reads/writes; the view itself only needs to bind
/// to `@Published` properties and call methods.
///
/// This is the first ViewModel extracted as part of the macOS↔iOS
/// separation work — the same class will drive both platforms' Chat
/// screen with only the SwiftUI layout differing.
@MainActor
final class ChatViewModel: ObservableObject {
  @Published var busy: Bool = false
  @Published var error: String?

  // Add-to-deck flow: triggered from the inline "+ Add" button on a
  // Portuguese phrase chip inside an assistant message.
  @Published var addToDeckPhrase: String = ""
  @Published var addToDeckEnglish: String = ""
  @Published var translatingPhrase: Bool = false
  @Published var showAddSheet: Bool = false

  let store: any DictionaryStoring
  let chatStore: ChatStore
  let translator: any LLMTranslating
  let tracker: ActivityTracker

  init(
    store: any DictionaryStoring,
    chatStore: ChatStore,
    translator: any LLMTranslating = EuroLLMTranslator.shared,
    tracker: ActivityTracker = .shared
  ) {
    self.store = store
    self.chatStore = chatStore
    self.translator = translator
    self.tracker = tracker
  }

  /// Send the current `chatStore.input` to the LLM as a user message,
  /// then append the assistant response (with tok/s stats) when it
  /// arrives. No-op while a send is already in flight.
  func send() {
    let trimmed = chatStore.input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !busy else { return }

    let userMessage = ChatMessage(role: .user, content: trimmed)
    chatStore.messages.append(userMessage)
    chatStore.input = ""
    error = nil
    busy = true

    let summary = tracker.contextualSummary()
    let prompt = ChatService.buildPrompt(
      messages: chatStore.messages,
      activitySummary: summary
    )

    Task { [weak self] in
      guard let self else { return }
      defer { Task { @MainActor in self.busy = false } }
      let start = Date()
      do {
        let response = try await self.translator.chat(prompt: prompt)
        let elapsed = Date().timeIntervalSince(start)
        let stats = ChatMessage.GenerationStats(
          elapsedSeconds: elapsed,
          estimatedTokens: max(1, response.count / 4)
        )
        // Sofia may emit an <action> block to perform an app action
        // on the student's behalf. Split it from the conversational
        // text, show the prose, then run the action and append its
        // result as its own message.
        let (action, cleaned) = ChatService.extractAction(from: response)
        await MainActor.run {
          if !cleaned.isEmpty {
            self.chatStore.messages.append(
              ChatMessage(role: .assistant, content: cleaned, generation: stats)
            )
          }
          if let action {
            let result = AppActionExecutor.execute(action, store: self.store)
            self.chatStore.messages.append(
              ChatMessage(role: .assistant, content: result.message)
            )
          }
        }
      } catch {
        await MainActor.run { self.error = error.localizedDescription }
      }
    }
  }

  /// Open the Add-to-Deck sheet for a Portuguese phrase and kick off a
  /// background LLM translation so the English field auto-populates.
  /// The user can edit the result before confirming.
  func startAddToDeck(phrase: String) {
    addToDeckPhrase = phrase
    addToDeckEnglish = ""
    translatingPhrase = true
    showAddSheet = true
    Task { [weak self] in
      guard let self else { return }
      defer { Task { @MainActor in self.translatingPhrase = false } }
      if let result = try? await self.translator.translate(
        phrase, direction: .portugueseToEnglish
      ) {
        await MainActor.run {
          self.addToDeckEnglish = result.translation.colloquial
        }
      }
    }
  }

  /// Commit the Add-to-Deck phrase as a new dictionary entry and
  /// dismiss the sheet. English falls back to the Portuguese form if
  /// the translation hasn't arrived (or the user cleared the field).
  func confirmAddToDeck() {
    store.addEntry(
      portuguese: addToDeckPhrase,
      english: addToDeckEnglish.isEmpty ? addToDeckPhrase : addToDeckEnglish,
      partOfSpeech: .phrase
    )
    showAddSheet = false
  }
}
