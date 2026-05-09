import Foundation

struct ChatMessage: Identifiable, Equatable {
  let id = UUID()
  let role: Role
  let content: String

  enum Role: String, CaseIterable {
    case user
    case assistant
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

  /// Build a single prompt string from the system prompt, optional activity
  /// context, and conversation history. The activity summary (from
  /// ActivityTracker) tells Sofia what the user has been doing in the app.
  static func buildPrompt(
    messages: [ChatMessage],
    activitySummary: String? = nil
  ) -> String {
    var parts: [String] = [systemPrompt]

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
}
