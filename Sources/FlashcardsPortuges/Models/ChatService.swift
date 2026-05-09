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
    You are a helpful European Portuguese language tutor. You answer questions \
    about Portuguese vocabulary, grammar, verb conjugations, pronunciation, \
    and cultural context. You can explain translations — why a particular word \
    or phrase is used, what nuance it carries, and how it differs from \
    alternatives. When relevant, provide example sentences in both Portuguese \
    and English. Keep answers friendly and informative. If you are unsure \
    about something, say so rather than guessing.
    """

  /// Build a single prompt string from the system prompt and conversation
  /// history. EuroLLM expects this classic instruct format.
  static func buildPrompt(messages: [ChatMessage]) -> String {
    var parts: [String] = [systemPrompt]

    for msg in messages {
      switch msg.role {
      case .user:
        parts.append("User: \(msg.content)")
      case .assistant:
        parts.append("Assistant: \(msg.content)")
      }
    }

    return parts.joined(separator: "\n\n")
  }
}
