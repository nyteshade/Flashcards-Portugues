import Foundation

@MainActor
class DictionaryStore: ObservableObject, DictionaryStoring {
  @Published var entries: [DictionaryEntry] = []
  @Published var decks: [Deck] = []
  @Published var activeDeckID: UUID
  @Published var groups: [DictionaryGroup] = []
  
  /// Default deck name used on first launch.
  static let defaultDeckName = "Study Deck"
  
  /// The currently-active study deck. Reads/writes go through here so
  /// the deck list always sees the same instance the UI is bound to.
  var studyDeck: Deck {
    get {
      if let idx = decks.firstIndex(where: { $0.id == activeDeckID }) {
        return decks[idx]
      }
      // Fallback — should never happen; activeDeckID is always
      // pinned to a deck in the list at init.
      return decks.first ?? Deck(name: Self.defaultDeckName, cards: [])
    }
    set {
      if let idx = decks.firstIndex(where: { $0.id == newValue.id }) {
        decks[idx] = newValue
        save()
      }
    }
  }
  
  private var fileURL: URL {
    PathProvider.appSupportDirectory.appendingPathComponent("dictionary.json")
  }

  private var decksURL: URL {
    PathProvider.appSupportDirectory.appendingPathComponent("decks.json")
  }

  private var groupsURL: URL {
    PathProvider.appSupportDirectory.appendingPathComponent("groups.json")
  }
  
  init() {
    // Bootstrap with an empty deck; load() will replace if present.
    let initial = Deck(name: Self.defaultDeckName, cards: [])
    decks = [initial]
    activeDeckID = initial.id
    load()
  }
  
  func load() {
    if let data = try? Data(contentsOf: fileURL),
       let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
      entries = decoded
    }
    if let data = try? Data(contentsOf: decksURL),
       let decoded = try? JSONDecoder().decode([Deck].self, from: data),
       !decoded.isEmpty {
      decks = decoded
      // Keep the previous "Study Deck" as the active one so
      // existing users land where they left off.
      if let study = decoded.first(where: { $0.name == Self.defaultDeckName }) {
        activeDeckID = study.id
      } else {
        activeDeckID = decoded[0].id
      }
    }
    if let data = try? Data(contentsOf: groupsURL),
       let decoded = try? JSONDecoder().decode([DictionaryGroup].self, from: data) {
      groups = decoded
    }
  }
  
  func save() {
    if let data = try? JSONEncoder().encode(entries) {
      try? data.write(to: fileURL, options: .atomic)
    }
    if let data = try? JSONEncoder().encode(decks) {
      try? data.write(to: decksURL, options: .atomic)
    }
    if let data = try? JSONEncoder().encode(groups) {
      try? data.write(to: groupsURL, options: .atomic)
    }
  }
  
  // MARK: - Dictionary entries
  
  func addEntry(portuguese: String, english: String, partOfSpeech: PartOfSpeech, notes: String = "", groupID: UUID? = nil) {
    let entry = DictionaryEntry(portuguese: portuguese, english: english, partOfSpeech: partOfSpeech, notes: notes, groupID: groupID)
    entries.append(entry)
    save()
  }

  func updateEntry(id: UUID, portuguese: String, english: String, partOfSpeech: PartOfSpeech, notes: String, groupID: UUID? = nil) {
    guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
    entries[idx].portuguese = portuguese
    entries[idx].english = english
    entries[idx].partOfSpeech = partOfSpeech
    entries[idx].notes = notes
    entries[idx].groupID = groupID
    save()
  }

  func removeEntry(_ entry: DictionaryEntry) {
    entries.removeAll { $0.id == entry.id }
    // Remove matching cards from all decks so orphans don't linger.
    for i in decks.indices {
      decks[i].cards.removeAll { !$0.isVerbCard && $0.portuguese == entry.portuguese }
    }
    save()
  }

  // MARK: - Groups

  func createGroup(named name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let group = DictionaryGroup(name: trimmed)
    groups.append(group)
    save()
  }

  func renameGroup(id: UUID, to newName: String) {
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let idx = groups.firstIndex(where: { $0.id == id }) else { return }
    groups[idx].name = trimmed
    save()
  }

  func deleteGroup(id: UUID) {
    // Unassign entries belonging to this group.
    for i in entries.indices where entries[i].groupID == id {
      entries[i].groupID = nil
    }
    groups.removeAll { $0.id == id }
    save()
  }

  func groupName(for entry: DictionaryEntry) -> String? {
    guard let gid = entry.groupID else { return nil }
    return groups.first(where: { $0.id == gid })?.name
  }

  // MARK: - Deck management
  
  /// Returns true iff `entry` already has a non-verb card in the active deck.
  func isEntryInActiveDeck(_ entry: DictionaryEntry) -> Bool {
    studyDeck.cards.contains { !$0.isVerbCard && $0.portuguese == entry.portuguese }
  }
  
  /// Toggle membership: add the entry as a card if absent, remove
  /// the matching card if present. Bookmark UX in DictionaryView
  /// depends on this.
  func toggleEntryInActiveDeck(_ entry: DictionaryEntry) {
    if let idx = decks.firstIndex(where: { $0.id == activeDeckID }) {
      if let cardIdx = decks[idx].cards.firstIndex(where: { !$0.isVerbCard && $0.portuguese == entry.portuguese }) {
        decks[idx].cards.remove(at: cardIdx)
      } else {
        let card = Flashcard(
          portuguese: entry.portuguese,
          english: entry.english,
          partOfSpeech: entry.partOfSpeech,
          notes: entry.notes
        )
        decks[idx].cards.append(card)
      }
      save()
    }
  }
  
  func addToStudyDeck(entry: DictionaryEntry) {
    guard let idx = decks.firstIndex(where: { $0.id == activeDeckID }) else { return }
    guard !decks[idx].cards.contains(where: { $0.portuguese == entry.portuguese && !$0.isVerbCard }) else { return }
    let card = Flashcard(
      portuguese: entry.portuguese,
      english: entry.english,
      partOfSpeech: entry.partOfSpeech,
      notes: entry.notes
    )
    decks[idx].cards.append(card)
    save()
  }
  
  func addVerbCardToStudyDeck(verb: String, english: String, tense: String, forms: [ConjugationFormData]) {
    guard let idx = decks.firstIndex(where: { $0.id == activeDeckID }) else { return }
    guard !decks[idx].cards.contains(where: { $0.verbInfinitive == verb && $0.tenseName == tense && $0.isVerbCard }) else { return }
    let card = Flashcard(
      portuguese: verb,
      english: english,
      partOfSpeech: .verb,
      isVerbCard: true,
      verbInfinitive: verb,
      tenseName: tense,
      conjugationForms: forms
    )
    decks[idx].cards.append(card)
    save()
  }
  
  func removeFromStudyDeck(_ card: Flashcard) {
    guard let idx = decks.firstIndex(where: { $0.id == activeDeckID }) else { return }
    decks[idx].cards.removeAll { $0.id == card.id }
    save()
  }
  
  // MARK: - Multi-deck operations
  
  /// Create a new empty deck and make it active.
  @discardableResult
  func createDeck(named name: String = "New Deck") -> Deck {
    let unique = uniqueDeckName(from: name)
    let new = Deck(name: unique, cards: [])
    decks.append(new)
    activeDeckID = new.id
    save()
    return new
  }
  
  func renameDeck(id: UUID, to newName: String) {
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let idx = decks.firstIndex(where: { $0.id == id }) else { return }
    decks[idx].name = uniqueDeckName(from: trimmed, ignoring: id)
    save()
  }

  /// Per-deck study direction. `false` = Portuguese first (tap →
  /// English/meaning side); `true` = English first (tap → Portuguese
  /// / conjugation side). Persisted with the deck.
  func setDeckReversed(_ reversed: Bool, deckID: UUID) {
    guard let idx = decks.firstIndex(where: { $0.id == deckID }) else { return }
    decks[idx].reversed = reversed
    save()
  }
  
  func deleteDeck(id: UUID) {
    decks.removeAll { $0.id == id }
    if decks.isEmpty {
      createDeck()
      return
    }
    if activeDeckID == id {
      activeDeckID = decks[0].id
    }
    save()
  }
  
  func duplicateDeck(id: UUID) {
    guard let original = decks.first(where: { $0.id == id }) else { return }
    var copy = original
    copy.id = UUID()
    copy.name = uniqueDeckName(from: original.name + " Copy")
    // New ids on each card so the duplicate's cards aren't aliased.
    copy.cards = original.cards.map { card in
      var c = card
      c.id = UUID()
      return c
    }
    decks.append(copy)
    save()
  }
  
  /// Replace the active deck with the supplied one (e.g. after Open
  /// Deck…). Adds the deck if its id isn't already in the list.
  func adoptDeck(_ deck: Deck, makeActive: Bool = true) {
    if let idx = decks.firstIndex(where: { $0.id == deck.id }) {
      decks[idx] = deck
    } else {
      // Avoid name collisions on import.
      var imported = deck
      imported.name = uniqueDeckName(from: deck.name)
      decks.append(imported)
      if makeActive { activeDeckID = imported.id }
    }
    if makeActive { activeDeckID = deck.id }
    save()
  }
  
  /// Generates a name not already used by another deck (case-insensitive).
  private func uniqueDeckName(from base: String, ignoring excluded: UUID? = nil) -> String {
    let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate = trimmed.isEmpty ? "Deck" : trimmed
    let existing = decks
      .filter { $0.id != excluded }
      .map { $0.name.lowercased() }
    guard existing.contains(candidate.lowercased()) else { return candidate }
    var n = 2
    while existing.contains("\(candidate) \(n)".lowercased()) { n += 1 }
    return "\(candidate) \(n)"
  }
}
