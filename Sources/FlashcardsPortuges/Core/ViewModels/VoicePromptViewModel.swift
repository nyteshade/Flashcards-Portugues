import Foundation

/// Owns the one-shot "you should download a better Portuguese voice"
/// banner state. Detection is delegated to `VoiceAvailability`;
/// snooze/dismiss state lives in UserDefaults so the prompt remembers
/// the user's last choice across launches.
///
/// Policy:
///   • Show if no Enhanced/Premium pt-PT voice is installed.
///   • "Open Settings" deep-links + snoozes for a week (the user
///     is presumably about to install something, no point nagging).
///   • "Not now" snoozes for a week.
///   • "Don't ask again" persists permanently.
@MainActor
final class VoicePromptViewModel: ObservableObject {
  @Published private(set) var shouldShow: Bool = false

  private let dismissedUntilKey = "voicePrompt.dismissedUntil"
  private let permanentlyDismissedKey = "voicePrompt.permanentlyDismissed"
  private let snoozeWindow: TimeInterval = 7 * 24 * 60 * 60

  init() {
    refresh()
  }

  /// Recompute `shouldShow` from current state. Cheap; safe to call
  /// repeatedly (e.g. when the app returns to foreground).
  func refresh() {
    let defaults = UserDefaults.standard
    if defaults.bool(forKey: permanentlyDismissedKey) {
      shouldShow = false
      return
    }
    let dismissedUntil = defaults.double(forKey: dismissedUntilKey)
    if dismissedUntil > Date().timeIntervalSince1970 {
      shouldShow = false
      return
    }
    shouldShow = VoiceAvailability.wantsUpgrade(for: .portuguese)
  }

  func openSettings() {
    #if os(macOS)
    VoiceAvailability.openVoiceSettings()
    #endif
    snooze()
  }

  func snooze() {
    UserDefaults.standard.set(
      Date().addingTimeInterval(snoozeWindow).timeIntervalSince1970,
      forKey: dismissedUntilKey
    )
    shouldShow = false
  }

  func dismissPermanently() {
    UserDefaults.standard.set(true, forKey: permanentlyDismissedKey)
    shouldShow = false
  }
}
