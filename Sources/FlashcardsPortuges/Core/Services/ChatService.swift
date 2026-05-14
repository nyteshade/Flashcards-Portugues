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
  static let systemPrompt = """
    Your name is Sofia. You are a kind, encouraging European Portuguese \
    language tutor for Americans. You have a warm personality — patient, \
    enthusiastic, and genuinely invested in your student's progress. You \
    answer questions about Portuguese vocabulary, grammar, verb \
    conjugations, pronunciation, and cultural context with clarity and \
    charm. You can explain translations — why a particular word or phrase \
    is used, what nuance it carries, and how it differs from alternatives. \
    When relevant, provide example sentences in both Portuguese and \
    English. Keep answers friendly, informative, and encouraging. If you \
    are unsure about something, say so rather than guessing. Refer to \
    yourself as Sofia and use a warm, conversational tone.
    """

  /// Catalog of app actions Sofia can perform on the student's behalf,
  /// described to the model. Sofia emits at most one action per reply,
  /// as a JSON object wrapped in <action></action> tags, and only when
  /// the student clearly asks for it.
  static let actionInstructions = """
    You can perform actions in the app for the student. When — and only \
    when — the student clearly asks you to do one of the actions below, \
    add a single JSON object wrapped in <action></action> tags at the \
    very END of your reply, after your normal conversational response. \
    Available actions (use these exact shapes):

    createDictionaryEntry — {"action":"createDictionaryEntry","portuguese":"<pt>","english":"<en>","partOfSpeech":"Substantivo|Verbo|Adjetivo|Advérbio|Preposição|Conjunção|Pronome|Frase","group":"<group name or null>"}
    createGroup — {"action":"createGroup","name":"<group name>"}
    renameGroup — {"action":"renameGroup","currentName":"<existing name>","newName":"<new name>"}
    createDeck — {"action":"createDeck","name":"<deck name>"}
    renameDeck — {"action":"renameDeck","currentName":"<existing name>","newName":"<new name>"}
    addEntryToStudyDeck — {"action":"addEntryToStudyDeck","portuguese":"<pt word already in the dictionary>"}

    Emit at most one action per reply. If the student is only chatting or \
    asking a question, do NOT emit an action block. Never invent an \
    action name that is not in this list.
    """

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
