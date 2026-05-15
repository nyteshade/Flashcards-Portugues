import Foundation

struct ChatMessage: Identifiable, Equatable {
  let id = UUID()
  let role: Role
  let content: String
  /// Generation telemetry for assistant messages. Always nil for user
  /// messages; nil-on-assistant means "couldn't measure" (e.g. an
  /// imported history message).
  var generation: GenerationStats? = nil

  enum Role: String, CaseIterable {
    case user
    case assistant
  }

  /// Lightweight tok/s estimate so the user can eyeball one variant's
  /// throughput vs another. Token count is a *rough* approximation —
  /// MLX's session.respond doesn't return a real token count and the
  /// tokenizer isn't exposed here. We use characters ÷ 4, which is
  /// close enough for cross-variant comparison.
  struct GenerationStats: Equatable {
    let elapsedSeconds: Double
    let estimatedTokens: Int

    var tokensPerSecond: Double {
      elapsedSeconds > 0 ? Double(estimatedTokens) / elapsedSeconds : 0
    }
  }
}

enum ChatService {
  /// Persona for Sofia. Bundled at Resources/Prompts/<scale>/chat-system.md
  /// (falls back to Resources/Prompts/default/chat-system.md). Edit
  /// that file to tune the persona — no rebuild changes needed beyond
  /// rerunning the app.
  static var systemPrompt: String { PromptLoader.load("chat-system") }

  /// Catalog of app actions Sofia can perform on the student's behalf.
  /// Bundled at Resources/Prompts/<scale>/chat-actions.md (falls back
  /// to default). Sofia emits at most one action per reply, wrapped
  /// in <action></action> tags, only when the student asks.
  static var actionInstructions: String { PromptLoader.load("chat-actions") }

  /// Build a single prompt string from the system prompt, the action
  /// catalog, optional activity context, and conversation history. The
  /// activity summary (from ActivityTracker) tells Sofia what the user
  /// has been doing in the app.
  static func buildPrompt(
    messages: [ChatMessage],
    activitySummary: String? = nil
  ) -> String {
    var parts: [String] = [systemPrompt, actionInstructions]

    // Inject activity context between system prompt and conversation.
    if let summary = activitySummary, !summary.isEmpty {
      parts.append(summary)
    }

    for msg in messages {
      switch msg.role {
      case .user:
        parts.append("User: \(msg.content)")
      case .assistant:
        parts.append("Sofia: \(msg.content)")
      }
    }

    return parts.joined(separator: "\n\n")
  }

  /// Pull an `AppAction` out of a model reply if one was emitted inside
  /// `<action></action>` tags. Returns the decoded action (or nil) plus
  /// the reply with the tag block stripped — the conversational
  /// remainder to show as the chat bubble.
  static func extractAction(from reply: String) -> (action: AppAction?, cleaned: String) {
    guard let open = reply.range(of: "<action>"),
          let close = reply.range(of: "</action>"),
          open.upperBound <= close.lowerBound else {
      return (nil, reply)
    }
    let jsonSlice = String(reply[open.upperBound..<close.lowerBound])
    let cleaned = (String(reply[..<open.lowerBound]) + String(reply[close.upperBound...]))
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let body = EuroLLMTranslator.extractJSONBody(from: jsonSlice),
          let data = body.data(using: .utf8),
          let action = try? JSONDecoder().decode(AppAction.self, from: data) else {
      // Tags present but unparseable — keep the cleaned text so the
      // user still sees Sofia's prose, just no action runs.
      return (nil, cleaned.isEmpty ? reply : cleaned)
    }
    return (action, cleaned)
  }
}
