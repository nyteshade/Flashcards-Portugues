import Foundation

/// Executes an `AppAction` (requested by the chat LLM) against the
/// dictionary store and returns a short human-readable result line to
/// echo back into the conversation. All resolution is name-based and
/// case-insensitive — the model only knows names, not UUIDs.
@MainActor
enum AppActionExecutor {
  /// Outcome of an action attempt. Both success and failure are
  /// surfaced to the student in the chat transcript.
  struct Result {
    let succeeded: Bool
    let message: String
  }

  static func execute(_ action: AppAction, store: any DictionaryStoring) -> Result {
    guard let kind = action.kind else {
      return Result(succeeded: false, message: "I don't know the action '\(action.action)'.")
    }
    switch kind {
    case .createDictionaryEntry: return createDictionaryEntry(action, store: store)
    case .createGroup:           return createGroup(action, store: store)
    case .renameGroup:           return renameGroup(action, store: store)
    case .createDeck:            return createDeck(action, store: store)
    case .renameDeck:            return renameDeck(action, store: store)
    case .addEntryToStudyDeck:   return addEntryToStudyDeck(action, store: store)
    }
  }

  // MARK: - Handlers

  private static func createDictionaryEntry(
    _ action: AppAction, store: any DictionaryStoring
  ) -> Result {
    guard let pt = nonEmpty(action.portuguese), let en = nonEmpty(action.english) else {
      return Result(succeeded: false, message: "I need both the Portuguese and English text to add an entry.")
    }
    let pos = PartOfSpeech.allCases.first {
      $0.rawValue.caseInsensitiveCompare(action.partOfSpeech ?? "") == .orderedSame
    } ?? .phrase

    var groupID: UUID?
    var groupNote = ""
    if let groupName = nonEmpty(action.group) {
      if let match = store.groups.first(where: {
        $0.name.caseInsensitiveCompare(groupName) == .orderedSame
      }) {
        groupID = match.id
      } else {
        groupNote = " (no group named \"\(groupName)\" — added it ungrouped)"
      }
    }

    store.addEntry(portuguese: pt, english: en, partOfSpeech: pos, notes: "", groupID: groupID)
    return Result(
      succeeded: true,
      message: "Added \"\(pt)\" → \"\(en)\" (\(pos.rawValue)) to your dictionary\(groupNote)."
    )
  }

  private static func createGroup(_ action: AppAction, store: any DictionaryStoring) -> Result {
    guard let name = nonEmpty(action.name) else {
      return Result(succeeded: false, message: "I need a name for the new group.")
    }
    if store.groups.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
      return Result(succeeded: false, message: "There's already a group called \"\(name)\".")
    }
    store.createGroup(named: name)
    return Result(succeeded: true, message: "Created the group \"\(name)\".")
  }

  private static func renameGroup(_ action: AppAction, store: any DictionaryStoring) -> Result {
    guard let current = nonEmpty(action.currentName), let new = nonEmpty(action.newName) else {
      return Result(succeeded: false, message: "I need both the current group name and the new name.")
    }
    guard let group = store.groups.first(where: {
      $0.name.caseInsensitiveCompare(current) == .orderedSame
    }) else {
      return Result(succeeded: false, message: "I couldn't find a group named \"\(current)\".")
    }
    store.renameGroup(id: group.id, to: new)
    return Result(succeeded: true, message: "Renamed the group \"\(current)\" to \"\(new)\".")
  }

  private static func createDeck(_ action: AppAction, store: any DictionaryStoring) -> Result {
    guard let name = nonEmpty(action.name) else {
      return Result(succeeded: false, message: "I need a name for the new deck.")
    }
    let deck = store.createDeck(named: name)
    return Result(succeeded: true, message: "Created the deck \"\(deck.name)\".")
  }

  private static func renameDeck(_ action: AppAction, store: any DictionaryStoring) -> Result {
    guard let current = nonEmpty(action.currentName), let new = nonEmpty(action.newName) else {
      return Result(succeeded: false, message: "I need both the current deck name and the new name.")
    }
    guard let deck = store.decks.first(where: {
      $0.name.caseInsensitiveCompare(current) == .orderedSame
    }) else {
      return Result(succeeded: false, message: "I couldn't find a deck named \"\(current)\".")
    }
    store.renameDeck(id: deck.id, to: new)
    return Result(succeeded: true, message: "Renamed the deck \"\(current)\" to \"\(new)\".")
  }

  private static func addEntryToStudyDeck(
    _ action: AppAction, store: any DictionaryStoring
  ) -> Result {
    guard let pt = nonEmpty(action.portuguese) else {
      return Result(succeeded: false, message: "I need the Portuguese word to add it to your study deck.")
    }
    guard let entry = store.entries.first(where: {
      $0.portuguese.caseInsensitiveCompare(pt) == .orderedSame
    }) else {
      return Result(succeeded: false, message: "\"\(pt)\" isn't in your dictionary yet — add it there first.")
    }
    store.addToStudyDeck(entry: entry)
    return Result(
      succeeded: true,
      message: "Added \"\(entry.portuguese)\" to the \"\(store.studyDeck.name)\" deck."
    )
  }

  // MARK: - Helpers

  private static func nonEmpty(_ s: String?) -> String? {
    guard let trimmed = s?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else { return nil }
    return trimmed
  }
}
