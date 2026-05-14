import Foundation

/// A user-facing app action the chat LLM can request on the student's
/// behalf. The model emits one of these as JSON inside `<action>` tags
/// at the end of a reply; `AppActionExecutor` runs it against the
/// `DictionaryStore`.
///
/// This is a flat struct with optional fields rather than a Codable
/// enum with associated values: a small local model emits flat JSON
/// far more reliably than nested or discriminated-union structures.
/// The `action` string is the discriminator; `kind` maps it to the
/// known set, and unknown strings are rejected by the executor.
struct AppAction: Codable, Equatable {
  let action: String

  // createDictionaryEntry
  var portuguese: String?
  var english: String?
  var partOfSpeech: String?
  var group: String?

  // createGroup / createDeck
  var name: String?

  // renameGroup / renameDeck
  var currentName: String?
  var newName: String?

  enum Kind: String {
    case createDictionaryEntry
    case createGroup
    case renameGroup
    case createDeck
    case renameDeck
    case addEntryToStudyDeck
  }

  var kind: Kind? { Kind(rawValue: action) }
}
