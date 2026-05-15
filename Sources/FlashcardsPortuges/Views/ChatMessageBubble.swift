import SwiftUI

/// Renders a single chat turn. Avatar + bubble + (for assistant
/// messages) the inline "Add to deck" hooks on Portuguese phrases.
/// Cross-platform — used by both `Views/macOS/ChatView` and
/// `Views/iOS/ChatView`.
struct MessageBubble: View {
  let message: ChatMessage
  var onAddToDeck: ((String) -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      if message.role == .assistant {
        avatar
      } else {
        Spacer(minLength: 60)
      }

      if message.role == .assistant {
        assistantBubble
      } else {
        userBubble
      }

      if message.role == .user {
        avatar
      } else {
        Spacer(minLength: 60)
      }
    }
  }

  @ViewBuilder
  private var userBubble: some View {
    Text(message.content)
      .font(.system(size: 15))
      .textSelection(.enabled)
      .padding(.horizontal, 12).padding(.vertical, 8)
      .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor))
      .foregroundStyle(.white)
  }

  @ViewBuilder
  private var assistantBubble: some View {
    VStack(alignment: .leading, spacing: 4) {
      bubbleBody
      if let gen = message.generation, gen.elapsedSeconds > 0 {
        Text(String(format: "~%.1f tok/s · %.1fs", gen.tokensPerSecond, gen.elapsedSeconds))
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .padding(.leading, 4)
      }
    }
  }

  @ViewBuilder
  private var bubbleBody: some View {
    let paragraphs = message.content
      .components(separatedBy: "\n")
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

    if paragraphs.isEmpty {
      Text(message.content)
        .font(.system(size: 15))
        .textSelection(.enabled)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.2)))
    } else {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
          RichMessageText(
            paragraph: para,
            onAddToDeck: onAddToDeck
          )
        }
      }
      .padding(.horizontal, 12).padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.2)))
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

/// Splits an assistant paragraph into alternating English / Portuguese
/// runs and renders each Portuguese run as a "chip" with inline
/// pronounce + add-to-deck buttons. Heuristic-driven — diacritic
/// anchors expand to adjacent non-English neighbors.
struct RichMessageText: View {
  let paragraph: String
  var onAddToDeck: ((String) -> Void)?

  var body: some View {
    let segments = parseSegments(paragraph)

    if segments.isEmpty {
      Text(paragraph)
        .font(.system(size: 15))
        .textSelection(.enabled)
    } else {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(segments) { seg in
          if seg.isPortuguese {
            portugueseChip(phrase: seg.text)
          } else {
            Text(seg.text)
              .font(.system(size: 15))
              .textSelection(.enabled)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func portugueseChip(phrase: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 2) {
      Text(phrase)
        .font(.system(size: 15))
        .italic()
        .foregroundStyle(.indigo)
        .textSelection(.enabled)

      Button {
        SpeechService.speak(phrase, language: .portuguese)
      } label: {
        Image(systemName: "speaker.wave.2")
          .font(.system(size: 11))
      }
      .buttonStyle(.plain)

      Button {
        onAddToDeck?(phrase)
      } label: {
        Image(systemName: "plus.circle")
          .font(.system(size: 11))
      }
      .buttonStyle(.plain)
    }
  }
}

// MARK: - Portuguese detection & segment parsing

private struct TextSegment: Identifiable {
  let id = UUID()
  let text: String
  let isPortuguese: Bool
}

private let ptDiacritics: Set<Character> = [
  "ã", "õ", "ç", "â", "ê", "ô",
  "á", "é", "í", "ó", "ú",
  "à", "è", "ì", "ò", "ù", "ü"
]

private let englishFunctionWords: Set<String> = [
  "the", "a", "an", "is", "are", "was", "were", "be", "been",
  "have", "has", "had", "do", "does", "did", "will", "would",
  "can", "could", "shall", "should", "may", "might", "must",
  "i", "you", "he", "she", "it", "we", "they",
  "me", "him", "her", "us", "them",
  "my", "your", "his", "its", "our", "their",
  "this", "that", "these", "those",
  "and", "or", "but", "if", "so", "as", "at", "by", "for",
  "in", "of", "on", "to", "with", "from", "about", "into",
  "not", "no", "yes", "than", "then", "also", "very", "just",
  "it's", "that's", "there's", "here's", "don't", "doesn't",
  "i'm", "you're", "he's", "she's", "we're", "they're",
  "isn't", "aren't", "wasn't", "weren't", "haven't", "hasn't",
  "hadn't", "won't", "wouldn't", "can't", "couldn't",
  "shouldn't", "mightn't", "mustn't",
  "what", "when", "where", "which", "who", "whom", "whose",
  "why", "how", "all", "any", "both", "each", "every",
  "more", "most", "other", "some", "such", "only",
  "up", "down", "out", "off", "over", "under", "again",
  "further", "once", "here", "there", "now", "then",
  "example", "examples", "note", "notes", "usage",
  "translation", "direct", "colloquial", "literal", "idiomatic"
]

private let englishPatterns: Set<String> = [
  "th", "ing", "tion", "ough", "ght", "ould", "eigh",
  "tial", "cial", "sion", "ment", "ness", "able", "ible",
  "less", "ship", "ward", "wise", "ize", "ise", "ify",
  "ology", "graph", "phil", "scope", "cycle"
]

private func looksPortugueseWord(_ word: String) -> Bool {
  let lower = word.lowercased()
  guard lower.contains(where: { ptDiacritics.contains($0) }) else { return false }
  if word.contains("'") { return false }
  for pat in englishPatterns {
    if lower.contains(pat) { return false }
  }
  return true
}

private func isEnglishWord(_ raw: String) -> Bool {
  let w = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
  if raw.contains("'") { return true }
  if raw.hasSuffix(":") { return true }
  if let first = raw.first, first.isUppercase, raw != raw.capitalized {
    return true
  }
  if w.rangeOfCharacter(from: .decimalDigits) != nil { return true }
  if englishFunctionWords.contains(w) { return true }
  for pat in englishPatterns {
    if w.contains(pat) { return true }
  }
  return false
}

private func parseSegments(_ para: String) -> [TextSegment] {
  let words = para.components(separatedBy: .whitespaces)
  guard !words.isEmpty else { return [] }

  let isAnchor = words.map { looksPortugueseWord($0) }
  guard isAnchor.contains(true) else { return [] }

  var inPortuguese = isAnchor
  var changed = true
  while changed {
    changed = false
    for i in 0..<words.count {
      if inPortuguese[i] { continue }
      let hasPortugueseNeighbor: Bool = {
        if i > 0 && inPortuguese[i - 1] { return true }
        if i < words.count - 1 && inPortuguese[i + 1] { return true }
        return false
      }()
      guard hasPortugueseNeighbor else { continue }
      guard !isEnglishWord(words[i]) else { continue }

      inPortuguese[i] = true
      changed = true
    }
  }

  var segments: [TextSegment] = []
  var i = 0
  while i < words.count {
    let start = i
    let isPT = inPortuguese[i]
    while i < words.count && inPortuguese[i] == isPT { i += 1 }
    let text = words[start..<i].joined(separator: " ")
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty {
      segments.append(TextSegment(text: trimmed, isPortuguese: isPT))
    }
  }

  segments = segments.filter { seg in
    if seg.isPortuguese {
      let count = seg.text.split(separator: " ").count
      return count >= 2
    }
    return true
  }

  return segments
}
