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
}

struct Deck: Identifiable, Codable, Hashable {
  var id = UUID()
  var name: String
  var cards: [Flashcard]
}
