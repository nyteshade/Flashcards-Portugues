import Foundation

/// Drives the Study tab — owns the deck-navigation pointer, search,
/// flip + shuffle state, define-popover state, and the verb-English
/// backfill cache. View stays a thin SwiftUI binding layer.
@MainActor
final class StudyViewModel: ObservableObject {
  // Card navigation
  @Published var currentIndex: Int = 0
  @Published var flipped: Bool = false
  @Published var searchText: String = ""
  @Published private(set) var shuffledOrder: [UUID] = []

  // Sheets / popovers
  @Published var showAddSheet: Bool = false
  @Published var showDefinePopover: Bool = false

  // Define popover state
  @Published private(set) var defineWord: String = ""
  @Published private(set) var defineResult: String?
  @Published private(set) var defineLLMResult: LLMDefinition?
  @Published private(set) var defineLLMError: String?
  @Published private(set) var defineLLMBusy: Bool = false

  // Deck rename
  @Published var renamingDeckID: UUID?
  @Published var renameDraft: String = ""

  // Lazy English fallback for verb cards whose stored english is
  // empty or equal to the tense name (legacy data).
  @Published private(set) var verbEnglishCache: [String: String] = [:]
  private var inFlightVerbLookups: Set<String> = []

  let store: any DictionaryStoring
  let translator: any LLMTranslating

  init(store: any DictionaryStoring, translator: any LLMTranslating = EuroLLMTranslator.shared) {
    self.store = store
    self.translator = translator
  }

  // MARK: - Derived state

  /// Cards in the currently-active deck, filtered by `searchText` and
  /// reordered by `shuffledOrder` (Randomize) when non-empty.
  var cards: [Flashcard] {
    let active = store.studyDeck
    let base: [Flashcard]
    if searchText.isEmpty {
      base = active.cards
    } else {
      base = active.cards.filter {
        $0.portuguese.localizedCaseInsensitiveContains(searchText) ||
        $0.english.localizedCaseInsensitiveContains(searchText)
      }
    }
    guard !shuffledOrder.isEmpty else { return base }
    let byId = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
    var ordered: [Flashcard] = shuffledOrder.compactMap { byId[$0] }
    let known = Set(shuffledOrder)
    ordered.append(contentsOf: base.filter { !known.contains($0.id) })
    return ordered
  }

  /// Current card with bounds-clamped index — searchText changes can
  /// shrink the filtered set under our feet.
  var currentCard: Flashcard {
    let list = cards
    let idx = max(0, min(currentIndex, list.count - 1))
    return list[idx]
  }

  var wordForDefine: String {
    flipped ? currentCard.english : currentCard.portuguese
  }

  // MARK: - Navigation

  func previous() {
    let list = cards
    guard !list.isEmpty else { return }
    let card = list[max(0, min(currentIndex, list.count - 1))]
    currentIndex = max(0, currentIndex - 1)
    flipped = false
    ActivityTracker.shared.record(
      category: .study,
      action: "Moved to previous card",
      detail: card.portuguese
    )
  }

  func next() {
    let list = cards
    guard !list.isEmpty else { return }
    let card = list[max(0, min(currentIndex, list.count - 1))]
    currentIndex = min(list.count - 1, currentIndex + 1)
    flipped = false
    ActivityTracker.shared.record(
      category: .study,
      action: "Moved to next card",
      detail: card.portuguese
    )
  }

  func flip() {
    flipped.toggle()
    let list = cards
    guard !list.isEmpty else { return }
    let card = list[max(0, min(currentIndex, list.count - 1))]
    if flipped {
      ActivityTracker.shared.record(
        category: .study,
        action: "Flipped card",
        detail: "'\(card.portuguese)' → '\(card.english)'"
      )
    }
  }

  func randomize() {
    shuffledOrder = store.studyDeck.cards.map { $0.id }.shuffled()
    currentIndex = 0
    flipped = false
  }

  /// Called by the view when the active deck changes — resets pointer
  /// and shuffle state so the user lands on card 1 of the new deck.
  func resetForActiveDeckChange() {
    currentIndex = 0
    flipped = false
    shuffledOrder.removeAll()
  }

  func removeCurrentCardFromDeck() {
    let card = currentCard
    store.removeFromStudyDeck(card)
    if currentIndex >= store.studyDeck.cards.count {
      currentIndex = max(0, store.studyDeck.cards.count - 1)
    }
  }

  // MARK: - Pronounce

  func speakCurrentCard() {
    let list = cards
    guard !list.isEmpty else { return }
    let card = list[max(0, min(currentIndex, list.count - 1))]
    if card.isVerbCard {
      if flipped {
        let text = card.conjugationForms
          .map { "\($0.pronoun) \($0.form)" }
          .joined(separator: ". ")
        SpeechService.speak(text)
      } else {
        SpeechService.speak("\(card.verbInfinitive) \(card.tenseName)")
      }
    } else {
      SpeechService.speak(card.portuguese)
    }
  }

  // MARK: - Define popover

  /// Open the Define popover for the current card. Local dictionary
  /// result is shown immediately; the SLM call runs in parallel and
  /// updates the popover when it lands.
  func triggerDefine() {
    let target = wordForDefine
    defineWord = target
    defineLLMResult = nil
    defineLLMError = nil
    defineResult = DictionaryLookup.define(target)
    showDefinePopover = true

    guard translator.isReady else { return }
    defineLLMBusy = true
    Task { [weak self] in
      guard let self else { return }
      do {
        let result = try await self.translator.defineWithExamples(portuguese: target)
        await MainActor.run {
          self.defineLLMResult = result
          self.defineLLMBusy = false
        }
      } catch {
        await MainActor.run {
          self.defineLLMError = error.localizedDescription
          self.defineLLMBusy = false
        }
      }
    }
  }

  func dismissDefinePopover() {
    showDefinePopover = false
  }

  // MARK: - Verb English backfill

  /// Resolve the English we should display for a verb card.
  /// Priority: card's stored english > dictionary entry > LLM-cached.
  func resolvedEnglishForVerbCard(_ card: Flashcard) -> String {
    let stored = card.english.trimmingCharacters(in: .whitespaces)
    if !stored.isEmpty && stored != card.tenseName {
      return stored
    }
    if let entry = store.entries.first(where: {
      $0.partOfSpeech == .verb &&
      $0.portuguese.caseInsensitiveCompare(card.verbInfinitive) == .orderedSame
    }), !entry.english.isEmpty, entry.english != card.tenseName {
      return entry.english
    }
    return verbEnglishCache[card.verbInfinitive.lowercased()] ?? ""
  }

  /// Kick off an SLM translate for a verb card's infinitive if it
  /// isn't already cached and the SLM is loaded. Cheap to call on
  /// every card appearance.
  func backfillVerbEnglishIfNeeded(_ card: Flashcard) {
    guard card.isVerbCard, translator.isReady else { return }
    let key = card.verbInfinitive.lowercased()
    if !resolvedEnglishForVerbCard(card).isEmpty { return }
    if inFlightVerbLookups.contains(key) { return }
    inFlightVerbLookups.insert(key)
    Task { [weak self] in
      guard let self else { return }
      do {
        let t = try await self.translator.translate(card.verbInfinitive, direction: .portugueseToEnglish)
        let candidate = t.translation.direct.isEmpty
          ? t.translation.colloquial
          : t.translation.direct
        await MainActor.run {
          if !candidate.isEmpty {
            self.verbEnglishCache[key] = candidate
          }
          self.inFlightVerbLookups.remove(key)
        }
      } catch {
        Logger.log("Verb backfill failed for \(card.verbInfinitive): \(error.localizedDescription)")
        await MainActor.run {
          self.inFlightVerbLookups.remove(key)
        }
      }
    }
  }

  // MARK: - Deck rename / open

  func beginRenamingDeck(_ deck: Deck) {
    renameDraft = deck.name
    renamingDeckID = deck.id
  }

  func commitDeckRename(id: UUID) {
    store.renameDeck(id: id, to: renameDraft)
    renamingDeckID = nil
  }

  func openDeckFromFile() {
    if let deck = DeckFileService.openDeck() {
      store.adoptDeck(deck, makeActive: true)
    }
  }
}
