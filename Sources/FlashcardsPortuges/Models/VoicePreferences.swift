import AVFoundation
import Foundation

/// User-level voice selection. Stored in `UserDefaults` keyed by
/// language so the user can pick a premium/enhanced voice once they've
/// downloaded one in System Settings.
@MainActor
final class VoicePreferences: ObservableObject {
    static let shared = VoicePreferences()

    private static let englishKey = "VoicePreferences.englishUSVoiceID"
    private static let portugueseKey = "VoicePreferences.portugueseVoiceID"

    /// Sensible defaults that exist on every macOS install. Used when
    /// the user hasn't explicitly chosen a voice for that language.
    /// Samantha is the only en-US female voice that ships with macOS;
    /// once the user downloads Ava/Allison/etc. they can pick those.
    static let defaultEnglishVoiceID = "com.apple.voice.compact.en-US.Samantha"
    static let defaultPortugueseVoiceID = "com.apple.voice.compact.pt-PT.Joana"

    @Published var englishUSVoiceID: String {
        didSet { UserDefaults.standard.set(englishUSVoiceID, forKey: Self.englishKey) }
    }

    @Published var portugueseVoiceID: String {
        didSet { UserDefaults.standard.set(portugueseVoiceID, forKey: Self.portugueseKey) }
    }

    private init() {
        self.englishUSVoiceID = UserDefaults.standard.string(forKey: Self.englishKey)
            ?? Self.defaultEnglishVoiceID
        self.portugueseVoiceID = UserDefaults.standard.string(forKey: Self.portugueseKey)
            ?? Self.defaultPortugueseVoiceID
    }

    /// Resolve the AVSpeechSynthesisVoice for `language` honoring the
    /// user's pick, falling back to the language's best system default
    /// when the saved id no longer resolves (e.g. voice was uninstalled).
    func voice(for language: SpeechService.Language) -> AVSpeechSynthesisVoice? {
        switch language {
        case .englishUS:
            return AVSpeechSynthesisVoice(identifier: englishUSVoiceID)
                ?? AVSpeechSynthesisVoice(identifier: Self.defaultEnglishVoiceID)
                ?? AVSpeechSynthesisVoice(language: "en-US")
        case .portuguese:
            return AVSpeechSynthesisVoice(identifier: portugueseVoiceID)
                ?? AVSpeechSynthesisVoice(identifier: Self.defaultPortugueseVoiceID)
                ?? AVSpeechSynthesisVoice(language: "pt-PT")
                ?? AVSpeechSynthesisVoice(language: "pt-BR")
        }
    }

    /// All installed voices that match `language`. Sorted by quality
    /// (premium > enhanced > default) then by name.
    static func availableVoices(for language: SpeechService.Language) -> [AVSpeechSynthesisVoice] {
        let prefixes: [String]
        switch language {
        case .englishUS: prefixes = ["en-US"]
        case .portuguese: prefixes = ["pt-PT", "pt-BR"]
        }
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { v in prefixes.contains { v.language.hasPrefix($0) } }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}

extension AVSpeechSynthesisVoice {
    /// Human-readable quality tag for the voice picker. macOS only
    /// exposes premium / enhanced / default.
    var qualityLabel: String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        case .default: return "Default"
        @unknown default: return "Default"
        }
    }
}
