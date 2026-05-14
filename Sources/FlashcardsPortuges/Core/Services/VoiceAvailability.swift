import AVFoundation
import Foundation

#if os(macOS)
import AppKit
#endif

/// Inspects installed `AVSpeechSynthesisVoice`s and offers a path to
/// the system voice-download UI. Apple does not let third-party apps
/// trigger voice installs; we can only detect what's installed and
/// deep-link the user to the relevant System Settings pane.
enum VoiceAvailability {
  enum Language: String {
    case portuguese = "pt-PT"
    case englishUS = "en-US"
  }

  /// True iff the user has only the basic `.default`-quality voice
  /// for `language` installed — i.e. they'd benefit from downloading
  /// an Enhanced or Premium pack. Returns false if no voice at all
  /// is installed (rare; nothing to prompt about) or if any voice is
  /// already Enhanced/Premium.
  static func wantsUpgrade(for language: Language) -> Bool {
    let voices = AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.hasPrefix(language.rawValue) }
    guard !voices.isEmpty else { return false }
    let hasGoodVoice = voices.contains {
      $0.quality == .enhanced || $0.quality == .premium
    }
    return !hasGoodVoice
  }

  #if os(macOS)
  /// Open the macOS System Settings pane where voices are managed.
  /// macOS reshuffles these anchors between versions; try the most
  /// specific link first and fall back to the bare Accessibility pane
  /// so the user is at least one click away from the right place.
  @MainActor
  static func openVoiceSettings() {
    let candidates = [
      // Sonoma+: dedicated Spoken Content pane.
      "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_SpokenContent",
      // Ventura: same domain, slightly different anchor.
      "x-apple.systempreferences:com.apple.preference.universalaccess?Spoken+Content",
      // Bare Accessibility pane as final fallback.
      "x-apple.systempreferences:com.apple.preference.universalaccess",
    ]
    for raw in candidates {
      if let url = URL(string: raw), NSWorkspace.shared.open(url) {
        return
      }
    }
  }
  #endif
}
