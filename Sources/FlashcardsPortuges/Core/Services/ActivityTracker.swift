import Foundation

struct ActivityEvent: Identifiable, Codable, Equatable {
  let id = UUID()
  let timestamp: Date
  let category: Category
  let action: String
  let detail: String?

  enum Category: String, CaseIterable, Codable {
    case navigation
    case study
    case audio
    case lookup
    case translate
    case verb
  }
}

/// Singleton that records user activity across the app and generates
/// a contextual summary for the Chat tab so the LLM knows what the
/// user has been doing — which cards they flipped, what they listened
/// to, translations they performed, etc.
@MainActor
final class ActivityTracker: ObservableObject {
  static let shared = ActivityTracker()

  @Published private(set) var events: [ActivityEvent] = []

  private let maxEvents = 80

  func record(category: ActivityEvent.Category, action: String, detail: String? = nil) {
    let event = ActivityEvent(
      timestamp: Date(),
      category: category,
      action: action,
      detail: detail
    )
    events.append(event)
    if events.count > maxEvents {
      events.removeFirst(events.count - maxEvents)
    }
  }

  /// Build a concise summary suitable for prepending to the LLM
  /// chat prompt. Groups events by category, deduplicates repeated
  /// actions, and limits to recent activity.
  func contextualSummary() -> String {
    let recent = events.suffix(60)
    guard !recent.isEmpty else { return "" }

    // Group and count repeated actions.
    var studyCards: [String: Int] = [:]       // "falar" → flip count
    var audioPlays: [String: Int] = [:]        // "falar (pt)" → count
    var lookups: [String] = []                 // "falar (Verbo)"
    var translations: [String] = []            // "hello → olá"
    var conjugations: [String] = []            // "falar — eu falo"
    var tabs: [String] = []                    // "Verbs", "Study"
    var cardDuration: (word: String, seconds: Double)?

    var lastFlipTime: Date?
    var lastFlipWord: String?

    for event in recent {
      switch event.category {
      case .study:
        if event.action.hasPrefix("Flipped ") {
          // Extract word from "Flipped card 'word'"
          if let detail = event.detail, let word = extractQuoted(detail) {
            studyCards[word, default: 0] += 1
            // Track timing between flips.
            if let last = lastFlipTime, lastFlipWord == word {
              let elapsed = event.timestamp.timeIntervalSince(last)
              cardDuration = (word: word, seconds: elapsed)
            }
            lastFlipTime = event.timestamp
            lastFlipWord = word
          }
        } else if event.action.hasPrefix("Moved to card") {
          // "Moved to card 3 of 12 in deck 'Verbs'"
          // Just note navigation; don't spam.
        } else if event.action.hasPrefix("Swiped") {
          // "Swiped left on 'falar'"
          if let detail = event.detail {
            studyCards[detail, default: 0] += 1
          }
        }

      case .audio:
        if let detail = event.detail {
          audioPlays[detail, default: 0] += 1
        }

      case .lookup:
        if let detail = event.detail {
          lookups.append(detail)
        }

      case .translate:
        if let detail = event.detail {
          translations.append(detail)
        }

      case .verb:
        if let detail = event.detail {
          conjugations.append(detail)
        }

      case .navigation:
        if let detail = event.detail {
          tabs.append(detail)
        }
      }
    }

    var lines: [String] = []

    // Last tab visited.
    if let lastTab = tabs.last {
      lines.append("Currently in \(lastTab) tab.")
    }

    // Cards studied.
    if !studyCards.isEmpty {
      let top = studyCards.sorted { $0.value > $1.value }.prefix(8)
      let parts = top.map { "'\($0.key)' (\($0.value)×)" }
      lines.append("Cards studied: \(parts.joined(separator: ", "))")
    }

    // Recent card timing.
    if let dur = cardDuration {
      lines.append("Last card '\(dur.word)' was viewed for ~\(Int(dur.seconds))s before flipping.")
    }

    // Audio plays.
    if !audioPlays.isEmpty {
      let top = audioPlays.sorted { $0.value > $1.value }.prefix(5)
      let parts = top.map { "'\($0.key)' (\($0.value)×)" }
      lines.append("Pronunciation listened: \(parts.joined(separator: ", "))")
    }

    // Lookups.
    let recentLookups = Array(lookups.suffix(5))
    if !recentLookups.isEmpty {
      lines.append("Looked up: \(recentLookups.joined(separator: ", "))")
    }

    // Translations.
    let recentTranslations = Array(translations.suffix(4))
    if !recentTranslations.isEmpty {
      lines.append("Translations: \(recentTranslations.joined(separator: "; "))")
    }

    // Conjugations.
    let recentConjugations = Array(conjugations.suffix(5))
    if !recentConjugations.isEmpty {
      lines.append("Conjugations explored: \(recentConjugations.joined(separator: ", "))")
    }

    guard !lines.isEmpty else { return "" }
    return "Recent user activity:\n" + lines.map { "• \($0)" }.joined(separator: "\n")
  }

  /// Reset tracked events (e.g. when starting a fresh chat session).
  func reset() {
    events.removeAll()
  }

  // MARK: - Helpers

  private func extractQuoted(_ text: String) -> String? {
    // Extract 'word' from text like "Flipped card 'falar (to speak)'"
    guard let start = text.firstIndex(of: "'") else { return nil }
    let after = text.index(after: start)
    guard let end = text[after...].firstIndex(of: "'") else { return nil }
    return String(text[after..<end])
  }
}
