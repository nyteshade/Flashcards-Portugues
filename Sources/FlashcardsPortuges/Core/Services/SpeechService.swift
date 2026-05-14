import Foundation
import AVFoundation

enum SpeechService {
  nonisolated(unsafe) private static let synthesizer = AVSpeechSynthesizer()
  
  enum Language {
    case portuguese       // pt-PT, falling back to pt-BR
    case englishUS        // en-US
  }
  
  /// Resolve the user-selected voice for `language` (or a sensible
  /// fallback). Wraps the access to MainActor-only `VoicePreferences`
  /// in a synchronous bridge — speech is fire-and-forget so any
  /// non-MainActor caller still gets a voice without async hops.
  @MainActor
  private static func resolvedVoice(for language: Language) -> AVSpeechSynthesisVoice? {
    VoicePreferences.shared.voice(for: language)
  }
  
  /// Default Portuguese pronunciation (back-compat for existing
  /// callers across the app that always wanted PT).
  @MainActor
  static func speak(_ word: String) {
    speak(word, language: .portuguese)
  }
  
  /// Pronounce `word` in the requested language. Slash-separated
  /// alternates like "você/ele/ela" are still split and spoken with
  /// brief pauses between them. Voice selection comes from
  /// `VoicePreferences` (user-configurable in Settings).
  @MainActor
  static func speak(_ word: String, language: Language) {
    let voice = resolvedVoice(for: language)
    let parts = word.components(separatedBy: "/")
    for (i, part) in parts.enumerated() {
      let trimmed = part.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      let utterance = AVSpeechUtterance(string: trimmed)
      utterance.voice = voice
      utterance.rate = 0.4
      utterance.pitchMultiplier = 1.0
      if i < parts.count - 1 {
        utterance.postUtteranceDelay = 0.3
      }
      synthesizer.speak(utterance)
    }
    let langLabel = language == .portuguese ? "pt" : "en"
    ActivityTracker.shared.record(
      category: .audio,
      action: "Played audio",
      detail: "'\(word)' (\(langLabel))"
    )
  }
  
  @MainActor
  static func speakConjugation(pronoun: String, form: String) {
    let voice = resolvedVoice(for: .portuguese)
    let parts = pronoun.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let hasSlash = pronoun.contains("/")
    for part in parts {
      let p = AVSpeechUtterance(string: part)
      p.voice = voice
      p.rate = 0.4
      if hasSlash {
        p.postUtteranceDelay = 0.15
      }
      synthesizer.speak(p)
    }
    let f = AVSpeechUtterance(string: form)
    f.voice = voice
    f.rate = 0.4
    if hasSlash {
      f.preUtteranceDelay = 0.1
    }
    synthesizer.speak(f)
  }
}
