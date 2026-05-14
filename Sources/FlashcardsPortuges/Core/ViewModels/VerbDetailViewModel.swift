import Foundation

/// One row in the "your verbs" chip strip across the top of the Verb
/// Conjugator. Identifiable on the Portuguese form so the SwiftUI
/// diffing stays stable even when English gets backfilled later.
struct VerbChip: Identifiable, Equatable {
  let portuguese: String
  var english: String
  var id: String { portuguese }
}

/// Drives the Verb Conjugator tab. Owns the input field, the
/// currently-resolved conjugation, the English fallback resolution
/// (prefilled → dictionary entry → SLM translation), and the chip
/// strip computed from the user's saved verb entries.
@MainActor
final class VerbDetailViewModel: ObservableObject {
  @Published var verbInput: String = ""
  @Published var verbEnglish: String = ""
  @Published private(set) var conjugation: VerbConjugation?
  @Published private(set) var errorMessage: String?
  @Published private(set) var verbChips: [VerbChip] = []

  let store: DictionaryStore
  let translator: EuroLLMTranslator

  init(store: DictionaryStore, translator: EuroLLMTranslator = .shared) {
    self.store = store
    self.translator = translator
  }

  /// Recompute the chip strip from the user's dictionary entries.
  /// Cheap to call; safe on every `store.entries` change.
  func refreshVerbChips() {
    verbChips = store.entries
      .filter { $0.partOfSpeech == .verb }
      .map { VerbChip(portuguese: $0.portuguese, english: $0.english) }
  }

  /// User picked a chip. Adopts its Portuguese + English and runs the
  /// lookup right away so the conjugation appears in one tap.
  func selectChip(_ chip: VerbChip) {
    verbInput = chip.portuguese
    verbEnglish = chip.english
    lookupVerb(prefilledEnglish: chip.english)
  }

  /// Conjugate the current `verbInput`. If the local conjugator
  /// doesn't recognize the term and the SLM is loaded, ask the SLM
  /// for the Portuguese infinitive (handles "to eat" → "comer") and
  /// retry.
  func lookupVerb(prefilledEnglish: String = "") {
    let v = verbInput.trimmingCharacters(in: .whitespaces).lowercased()
    guard !v.isEmpty else { return }

    if let result = VerbConjugator.conjugate(v, english: prefilledEnglish) {
      applyConjugationResult(result, originalInput: v, prefilledEnglish: prefilledEnglish)
      return
    }

    // Conjugator missed. If the SLM is loaded, try to resolve the
    // input as English, e.g. "to go" -> "ir".
    guard translator.isReady else {
      conjugation = nil
      errorMessage = "\"\(v)\" is not a valid Portuguese verb. Verbs end in -ar, -er, or -ir."
      return
    }

    errorMessage = nil
    Task { [weak self] in
      guard let self else { return }
      guard let inf = await self.translator.portugueseInfinitive(forEnglish: v) else {
        await MainActor.run {
          self.conjugation = nil
          self.errorMessage = "\"\(v)\" is not a valid Portuguese verb. Verbs end in -ar, -er, or -ir."
        }
        return
      }
      await MainActor.run {
        self.verbInput = inf
        if let result = VerbConjugator.conjugate(inf, english: "") {
          // Cache the original English so the page header
          // shows the user's term back to them.
          self.verbEnglish = VerbEnglishFormatter.normalize(v)
          self.applyConjugationResult(result, originalInput: inf, prefilledEnglish: self.verbEnglish)
        } else {
          self.errorMessage = "Resolved “\(v)” to “\(inf)”, but no conjugation table was found."
          self.conjugation = nil
        }
      }
    }
  }

  /// Shared post-conjugate handler. Resolves the displayed English
  /// translation in priority order (prefilled > dictionary entry >
  /// SLM) and stores the resulting `VerbConjugation`.
  private func applyConjugationResult(_ result: VerbConjugation, originalInput v: String, prefilledEnglish: String) {
    conjugation = result
    errorMessage = nil

    if !prefilledEnglish.isEmpty {
      verbEnglish = prefilledEnglish
    } else if let entry = store.entries.first(where: { $0.partOfSpeech == .verb && $0.portuguese.caseInsensitiveCompare(v) == .orderedSame }) {
      verbEnglish = entry.english
    } else {
      verbEnglish = ""
      if translator.isReady {
        Task { [weak self] in
          guard let self else { return }
          do {
            let t = try await self.translator.translate(v, direction: .portugueseToEnglish)
            // Verbs render best with the direct translation
            // (e.g. "to eat" rather than "consume"). Fall back to
            // colloquial only if the model omitted direct.
            let candidate = t.translation.direct.isEmpty
              ? t.translation.colloquial
              : t.translation.direct
            await MainActor.run {
              self.verbEnglish = candidate
              if let idx = self.verbChips.firstIndex(where: { $0.portuguese.caseInsensitiveCompare(v) == .orderedSame }) {
                self.verbChips[idx].english = candidate
              }
            }
          } catch {
            Logger.log("Verb translation failed for \(v): \(error.localizedDescription)")
          }
        }
      }
    }
  }
}
