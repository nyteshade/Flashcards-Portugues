import SwiftUI

// MARK: - Main view

struct ChatView: View {
  @ObservedObject var store: DictionaryStore
  @ObservedObject private var translator = EuroLLMTranslator.shared
  @ObservedObject private var tracker = ActivityTracker.shared

  @State private var messages: [ChatMessage] = []
  @State private var input: String = ""
  @State private var busy = false
  @State private var error: String?

  @State private var addToDeckPhrase: String = ""
  @State private var addToDeckEnglish: String = ""
  @State private var translatingPhrase = false
  @State private var showAddSheet = false

  @FocusState private var inputFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      messageList
      Divider()
      inputBar
    }
    .onAppear { inputFocused = true }
    .sheet(isPresented: $showAddSheet) {
      addToDeckSheet
    }
  }

  // MARK: - Message list

  @ViewBuilder
  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if messages.isEmpty { emptyState }

          ForEach(messages) { msg in
            MessageBubble(message: msg, onAddToDeck: { phrase in
              addToDeckPhrase = phrase
              addToDeckEnglish = ""
              translatingPhrase = true
              showAddSheet = true
              // Fire off LLM translation in background.
              Task {
                defer {
                  Task { @MainActor in translatingPhrase = false }
                }
                if let result = try? await translator.translate(
                  phrase, direction: .portugueseToEnglish
                ) {
                  await MainActor.run {
                    addToDeckEnglish = result.translation.colloquial
                  }
                }
              }
            })
            .id(msg.id)
          }

          if busy { thinkingRow }

          if let error = error {
            Text(error)
              .font(.system(size: 13))
              .foregroundStyle(.red)
              .padding(.horizontal, 16)
          }

          Color.clear.frame(height: 1).id("bottomAnchor")
        }
        .padding(16)
        .frame(maxWidth: .infinity)
      }
      .defaultScrollAnchor(.bottom)
      .onChange(of: messages.count) { _, _ in
        withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
      }
      .onChange(of: busy) { _, newValue in
        if newValue { withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) } }
      }
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer().frame(height: 60)
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 40)).foregroundStyle(.secondary)
      Text("Ask Sofia about Portuguese")
        .font(.title3).foregroundStyle(.secondary)
      Text("Translation nuances, grammar, verb tenses, cultural context — anything language-related.")
        .font(.callout).foregroundStyle(.tertiary)
        .multilineTextAlignment(.center).frame(maxWidth: 360)
      Spacer().frame(height: 60)
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var thinkingRow: some View {
    HStack(spacing: 8) {
      ProgressView().controlSize(.small)
      Text("Sofia is thinking…")
        .font(.system(size: 14)).foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 4).padding(.vertical, 6)
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
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .onKeyPress(keys: [.return], phases: .down) { keyPress in
          if keyPress.modifiers.contains(.shift) { return .ignored }
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

  // MARK: - Add to deck sheet

  @ViewBuilder
  private var addToDeckSheet: some View {
    VStack(spacing: 16) {
      Text("Add to Study Deck")
        .font(.headline)

      VStack(alignment: .leading, spacing: 6) {
        Text("Portuguese").font(.caption).foregroundStyle(.secondary)
        Text(addToDeckPhrase)
          .font(.system(size: 15, weight: .medium))
          .italic()
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("English translation").font(.caption).foregroundStyle(.secondary)
        HStack(spacing: 6) {
          TextField("Enter English translation…", text: $addToDeckEnglish)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 15))
          if translatingPhrase {
            ProgressView()
              .controlSize(.small)
          }
        }
      }

      HStack(spacing: 12) {
        Button("Cancel") { showAddSheet = false }
          .keyboardShortcut(.escape)
        Spacer()
        Button("Add to Deck") {
          store.addEntry(
            portuguese: addToDeckPhrase,
            english: addToDeckEnglish.isEmpty ? addToDeckPhrase : addToDeckEnglish,
            partOfSpeech: .phrase
          )
          showAddSheet = false
        }
        .buttonStyle(.borderedProminent)
        .disabled(addToDeckEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding()
    .frame(width: 380)
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
      defer { Task { @MainActor in busy = false } }
      do {
        let response = try await translator.chat(prompt: prompt)
        await MainActor.run {
          messages.append(ChatMessage(role: .assistant, content: response))
        }
      } catch {
        await MainActor.run { self.error = error.localizedDescription }
      }
    }
  }
}

// MARK: - Message bubble

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

// MARK: - Rich message text (mixed English + Portuguese with inline buttons)

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
      .help("Pronounce")

      Button {
        onAddToDeck?(phrase)
      } label: {
        Image(systemName: "plus.circle")
          .font(.system(size: 11))
      }
      .buttonStyle(.plain)
      .help("Add to study deck")
    }
  }
}

// MARK: - Portuguese detection & segment parsing

/// A segment of text within a paragraph, tagged as Portuguese or English.
private struct TextSegment: Identifiable {
  let id = UUID()
  let text: String
  let isPortuguese: Bool
}

/// The set of characters that strongly indicate European Portuguese.
private let ptDiacritics: Set<Character> = [
  "ã", "õ", "ç", "â", "ê", "ô",
  "á", "é", "í", "ó", "ú",
  "à", "è", "ì", "ò", "ù", "ü"
]

/// Known English function words — stop Portuguese expansion.
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

/// English-centric letter patterns — if a word contains these it's
/// unlikely to be Portuguese.
private let englishPatterns: Set<String> = [
  "th", "ing", "tion", "ough", "ght", "ould", "eigh",
  "tial", "cial", "sion", "ment", "ness", "able", "ible",
  "less", "ship", "ward", "wise", "ize", "ise", "ify",
  "ology", "graph", "phil", "scope", "cycle"
]

/// Heuristic: does a word look Portuguese (not English)?
private func looksPortugueseWord(_ word: String) -> Bool {
  let lower = word.lowercased()
  // Must contain at least one Portuguese diacritic.
  guard lower.contains(where: { ptDiacritics.contains($0) }) else { return false }
  // Apostrophes are English contractions.
  if word.contains("'") { return false }
  // Reject if it contains English-specific patterns.
  for pat in englishPatterns {
    if lower.contains(pat) { return false }
  }
  return true
}

/// Is this word clearly English and should stop Portuguese expansion?
private func isEnglishWord(_ raw: String) -> Bool {
  let w = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
  // Apostrophe → English contraction.
  if raw.contains("'") { return true }
  // Colon-terminated words are labels / metadata, not content.
  if raw.hasSuffix(":") { return true }
  // Mid-sentence capital letter → English proper noun or new clause.
  if let first = raw.first, first.isUppercase, raw != raw.capitalized {
    return true
  }
  // Numbers → not Portuguese.
  if w.rangeOfCharacter(from: .decimalDigits) != nil { return true }
  // Known English function words.
  if englishFunctionWords.contains(w) { return true }
  // Contains English patterns.
  for pat in englishPatterns {
    if w.contains(pat) { return true }
  }
  return false
}

/// Parse a paragraph into alternating English / Portuguese segments.
/// Portuguese segments are text runs that contain Portuguese-looking
/// words, expanded to include adjacent non-English words.
private func parseSegments(_ para: String) -> [TextSegment] {
  // Tokenize: split on whitespace while tracking positions.
  let words = para.components(separatedBy: .whitespaces)
  guard !words.isEmpty else { return [] }

  // Mark which word indices are Portuguese anchors.
  var isAnchor = words.map { looksPortugueseWord($0) }
  guard isAnchor.contains(true) else { return [] }

  // Expand anchors: pull in adjacent non-English words.
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
      // Stop at any English word.
      guard !isEnglishWord(words[i]) else { continue }

      inPortuguese[i] = true
      changed = true
    }
  }

  // Build segments: consecutive Portuguese/non-Portuguese runs.
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

  // Filter out single-word Portuguese "segments" that are just
  // prepositions or articles — they're noise.
  segments = segments.filter { seg in
    if seg.isPortuguese {
      let count = seg.text.split(separator: " ").count
      return count >= 2
    }
    return true
  }

  return segments
}
