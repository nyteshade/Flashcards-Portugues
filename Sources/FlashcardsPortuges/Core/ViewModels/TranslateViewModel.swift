import Foundation
import NaturalLanguage

/// Owns the Translate tab's input + LLM result state and the Speak
/// button's language-detection policy. View binds via @Published
/// properties; the LLM Task + NLLanguageRecognizer call live here.
@MainActor
final class TranslateViewModel: ObservableObject {
  @Published var input: String = ""
  @Published private(set) var result: LLMTranslation?
  @Published private(set) var detectedDirection: LLMDirection?
  @Published private(set) var error: String?
  @Published private(set) var busy: Bool = false

  let translator: any LLMTranslating

  init(translator: any LLMTranslating = EuroLLMTranslator.shared) {
    self.translator = translator
  }

  /// Run the bidirectional translate on the current input. Pushes
  /// busy → result/detectedDirection (success) or error (failure) so
  /// the view re-renders.
  func runTranslate() {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    busy = true
    error = nil

    Task { [weak self] in
      guard let self else { return }
      defer { Task { @MainActor in self.busy = false } }
      do {
        let outcome = try await self.translator.autoTranslate(trimmed)
        await MainActor.run {
          self.result = outcome.translation
          self.detectedDirection = outcome.direction
          ActivityTracker.shared.record(
            category: .translate,
            action: "Translated text",
            detail: "'\(trimmed)' → '\(outcome.translation.translation.direct)'"
          )
        }
      } catch {
        await MainActor.run {
          self.error = error.localizedDescription
          self.result = nil
          self.detectedDirection = nil
        }
      }
    }
  }

  /// Speak the current input, picking the voice via
  /// `detectedLanguageForInput`.
  func speakInput() {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    SpeechService.speak(trimmed, language: detectedLanguageForInput(trimmed))
  }

  /// Map a translation snippet to the (portuguese, english) pair
  /// callers can feed to add-to-deck UI so the entry is added in the
  /// correct slot.
  func pairedTextForResult(otherSide translated: String, direction: LLMDirection) -> (portuguese: String, english: String) {
    let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
    switch direction {
    case .englishToPortuguese:
      return (portuguese: translated, english: trimmedInput)
    case .portugueseToEnglish:
      return (portuguese: trimmedInput, english: translated)
    }
  }

  /// Pick the voice language for the Speak button. Policy:
  ///   1. If the user has already translated, trust the LLM's call.
  ///   2. Any Portuguese-distinctive diacritic appears → Portuguese.
  ///   3. `NLLanguageRecognizer` reports English ≥ 0.85 → English.
  ///   4. Otherwise default to Portuguese.
  func detectedLanguageForInput(_ text: String) -> SpeechService.Language {
    if let direction = detectedDirection {
      switch direction {
      case .englishToPortuguese: return .englishUS
      case .portugueseToEnglish: return .portuguese
      }
    }

    let portugueseSignals: Set<Character> = ["ã", "õ", "â", "ê", "ô", "ç", "á", "í", "ó", "ú", "à"]
    if text.lowercased().contains(where: { portugueseSignals.contains($0) }) {
      return .portuguese
    }

    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
    if let englishConfidence = hypotheses[.english], englishConfidence >= 0.85 {
      return .englishUS
    }
    return .portuguese
  }
}
