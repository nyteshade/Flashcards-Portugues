import Foundation

/// The slice of `DictionaryStore` that ViewModels depend on.
///
/// ViewModels hold `any DictionaryStoring` rather than the concrete
/// class so they can be unit-tested against an in-memory fake. Views
/// keep using the concrete `DictionaryStore` directly — SwiftUI's
/// `@ObservedObject` / `@StateObject` need a concrete `ObservableObject`,
/// and views aren't unit-tested anyway.
///
/// This protocol intentionally exposes only what the VMs call. If a VM
/// starts needing another `DictionaryStore` method, add it here.
@MainActor
protocol DictionaryStoring: AnyObject {
  var entries: [DictionaryEntry] { get set }
  var groups: [DictionaryGroup] { get }
  var decks: [Deck] { get }
  var studyDeck: Deck { get }

  func addEntry(
    portuguese: String,
    english: String,
    partOfSpeech: PartOfSpeech,
    notes: String,
    groupID: UUID?
  )
  func removeEntry(_ entry: DictionaryEntry)
  func createGroup(named name: String)
  func renameGroup(id: UUID, to newName: String)
  func deleteGroup(id: UUID)
  func addToStudyDeck(entry: DictionaryEntry)
  func removeFromStudyDeck(_ card: Flashcard)
  @discardableResult
  func createDeck(named name: String) -> Deck
  func renameDeck(id: UUID, to newName: String)
  func adoptDeck(_ deck: Deck, makeActive: Bool)
  func save()
}

extension DictionaryStoring {
  /// Convenience matching `DictionaryStore`'s defaulted parameters —
  /// protocol requirements can't carry default values, so the
  /// `notes`/`groupID`-less call site is provided here.
  func addEntry(portuguese: String, english: String, partOfSpeech: PartOfSpeech) {
    addEntry(
      portuguese: portuguese,
      english: english,
      partOfSpeech: partOfSpeech,
      notes: "",
      groupID: nil
    )
  }
}
