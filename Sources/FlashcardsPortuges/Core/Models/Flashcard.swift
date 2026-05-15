import Foundation

struct ConjugationFormData: Codable, Hashable {
  let pronoun: String
  let form: String
}

enum PartOfSpeech: String, Codable, CaseIterable, Identifiable {
  case verb = "Verbo"
  case noun = "Substantivo"
  case adjective = "Adjetivo"
  case adverb = "Advérbio"
  case preposition = "Preposição"
  case conjunction = "Conjunção"
  case pronoun = "Pronome"
  case phrase = "Frase"
  
  var id: String { rawValue }
}

struct Flashcard: Identifiable, Codable, Hashable {
  var id = UUID()
  var portuguese: String
  var english: String
  var partOfSpeech: PartOfSpeech
  var notes: String = ""
  var createdAt: Date = Date()
  var proficiency: Int = 0
  var nextReview: Date = Date()
  var isVerbCard: Bool = false
  var verbInfinitive: String = ""
  var tenseName: String = ""
  var conjugationForms: [ConjugationFormData] = []
}

struct DictionaryEntry: Identifiable, Codable {
  var id = UUID()
  var portuguese: String
  var english: String
  var partOfSpeech: PartOfSpeech
  var notes: String = ""
  var groupID: UUID? = nil
}

struct DictionaryGroup: Identifiable, Codable {
  var id = UUID()
  var name: String
}

struct Deck: Identifiable, Codable, Hashable {
  var id = UUID()
  var name: String
  var cards: [Flashcard]
  /// Default study direction. `false` = Portuguese-first (tap to
  /// reveal English); `true` = English-first (tap to reveal Portuguese
  /// / conjugation side). Per-deck so different decks can be studied
  /// in different directions.
  var reversed: Bool = false

  init(id: UUID = UUID(), name: String, cards: [Flashcard], reversed: Bool = false) {
    self.id = id
    self.name = name
    self.cards = cards
    self.reversed = reversed
  }

  enum CodingKeys: CodingKey { case id, name, cards, reversed }

  // Custom decoder so old `.flcd` files without `reversed` still load.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    self.name = try c.decode(String.self, forKey: .name)
    self.cards = try c.decode([Flashcard].self, forKey: .cards)
    self.reversed = try c.decodeIfPresent(Bool.self, forKey: .reversed) ?? false
  }
}
