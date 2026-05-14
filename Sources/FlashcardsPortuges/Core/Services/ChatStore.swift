import Foundation

/// Shared state for the Chat tab. Lifting messages/input out of
/// `ChatView` lets other tabs (e.g. the Dictionary's "Chat about this"
/// button) pre-fill the input and trigger focus before the user
/// switches to the Chat tab.
@MainActor
final class ChatStore: ObservableObject {
  @Published var messages: [ChatMessage] = []
  @Published var input: String = ""
  /// Bumped whenever an external caller wants the chat input to take
  /// focus (e.g. after `prefill`). `ChatView` watches this token and
  /// re-focuses the text editor on each change.
  @Published var focusToken: Int = 0

  /// Replace the input with `text` and request focus. Existing
  /// in-progress drafts are overwritten — callers should only invoke
  /// this when the user clearly intends to start a new prompt.
  func prefill(_ text: String) {
    input = text
    focusToken &+= 1
  }

  /// Clear the conversation and input to start a fresh session with
  /// Sofia. The LLM keeps no server-side state — the whole context is
  /// these `messages`, rebuilt into the prompt on every send — so
  /// emptying them is a complete reset, no app restart needed.
  func startNewSession() {
    messages.removeAll()
    input = ""
    focusToken &+= 1
  }
}
