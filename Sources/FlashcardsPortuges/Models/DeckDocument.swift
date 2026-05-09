import Foundation

/// On-disk wrapper around a `Deck`. Versioned so we can grow the
/// schema later without breaking existing files. Stored as plain
/// JSON with the `.flcd` extension. (Plain JSON for now; switching
/// to a zipped package only when we need attachments.)
struct DeckDocument: Codable {
  static let currentFormatVersion = 1
  static let fileExtension = "flcd"
  
  let formatVersion: Int
  let createdAt: Date
  let appVersion: String
  let deck: Deck
  
  init(deck: Deck) {
    self.formatVersion = Self.currentFormatVersion
    self.createdAt = Date()
    self.appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    self.deck = deck
  }
}

enum DeckIO {
  enum IOError: LocalizedError {
    case unsupportedFormatVersion(Int)
    case decodeFailed(String)
    
    var errorDescription: String? {
      switch self {
      case .unsupportedFormatVersion(let v):
        return "Unsupported deck format version: \(v). Update the app to open this file."
      case .decodeFailed(let reason):
        return "Could not read deck file: \(reason)"
      }
    }
  }
  
  static func write(deck: Deck, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let doc = DeckDocument(deck: deck)
    let data = try encoder.encode(doc)
    try data.write(to: url, options: .atomic)
  }
  
  static func read(from url: URL) throws -> Deck {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      let doc = try decoder.decode(DeckDocument.self, from: data)
      guard doc.formatVersion <= DeckDocument.currentFormatVersion else {
        throw IOError.unsupportedFormatVersion(doc.formatVersion)
      }
      return doc.deck
    } catch let e as IOError {
      throw e
    } catch {
      // Older files (pre-DeckDocument) might be a bare Deck JSON.
      // Try that as a courtesy fallback.
      if let bare = try? decoder.decode(Deck.self, from: data) {
        return bare
      }
      throw IOError.decodeFailed(String(describing: error))
    }
  }
  
  /// Render a deck as readable Markdown. One-way export — re-opening
  /// requires the `.flcd` form.
  static func markdown(for deck: Deck) -> String {
    var out = "# \(deck.name)\n\n"
    let phrases = deck.cards.filter { !$0.isVerbCard }
    let verbs = deck.cards.filter { $0.isVerbCard }
    
    if !phrases.isEmpty {
      out += "## Phrases & Vocabulary\n\n"
      for card in phrases {
        let pos = card.partOfSpeech.rawValue
        out += "- **\(card.portuguese)** — \(card.english)"
        if !card.notes.isEmpty {
          out += " *(\(card.notes))*"
        }
        out += "  _\(pos)_\n"
      }
      out += "\n"
    }
    
    if !verbs.isEmpty {
      out += "## Verbs\n\n"
      for card in verbs {
        let englishLabel = card.english.isEmpty
        ? card.verbInfinitive
        : "\(card.verbInfinitive) (\(VerbEnglishFormatter.normalize(card.english)))"
        out += "### \(englishLabel) · \(card.tenseName)\n\n"
        out += "| Pronoun | Form |\n|---|---|\n"
        for form in card.conjugationForms {
          out += "| \(form.pronoun) | \(form.form) |\n"
        }
        out += "\n"
      }
    }
    return out
  }
}
