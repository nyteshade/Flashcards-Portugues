import AVFoundation
import Darwin
import SwiftUI

/// iOS app entry point. Mirrors the macOS app's startup steps
/// (DictionaryStore + EuroLLM auto-load) without AppKit, the
/// AppDelegate, or the macOS-only `Settings` scene — iOS reaches
/// settings via a pushed view from `ContentView`.
@main
struct FlashcardsPortugesIOSApp: App {
  @StateObject private var store = DictionaryStore()

  init() {
    Logger.log("FlashcardsPortugesIOSApp started.")
    Self.prepareHuggingFaceEnvironment()
    Self.prepareAudioSession()
    EuroLLMTranslator.shared.autoLoadIfCached()
  }

  /// Configure AVAudioSession so AVSpeechSynthesizer actually plays
  /// audio on a real iPhone. iOS's default audio category is
  /// `.soloAmbient`, which:
  ///   - Goes silent when the Ring/Silent hardware switch is set to
  ///     silent.
  ///   - Doesn't mix with or duck other audio.
  /// For a language-learning app we want to hear pronunciations
  /// even with the device on silent (the user explicitly tapped a
  /// speaker button — clear intent), so use `.playback` mixed with
  /// `.spokenAudio` mode and duck other audio briefly. macOS has no
  /// AVAudioSession and works as-is.
  private static func prepareAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playback,
        mode: .spokenAudio,
        options: [.duckOthers]
      )
      try session.setActive(true)
      Logger.log("AVAudioSession ready (.playback / .spokenAudio)")
    } catch {
      Logger.log("AVAudioSession setup failed: \(error.localizedDescription)")
    }
  }

  /// Pre-populate the env vars that MLX / swift-huggingface /
  /// swift-transformers consult so the C++ side never hits
  /// `_LIBCPP_ASSERT_NON_NULL(__s != nullptr,
  /// "basic_string(const char*) detected nullptr")`. iOS apps don't
  /// inherit a user shell environment, so any C++ call site that
  /// wraps `getenv(...)` directly in `std::string` blows up. We set
  /// everything plausibly read by the HF stack to a non-null value:
  ///
  ///   - HF_HUB_CACHE / HF_HOME / TRANSFORMERS_CACHE → our cache dir
  ///   - HF_TOKEN / HUGGING_FACE_HUB_TOKEN → empty string (public)
  ///   - XDG_CACHE_HOME → app caches root
  ///   - HOME / USER / LOGNAME → harmless non-empty fallbacks if
  ///     they happen to be unset (Apple usually provides HOME)
  ///
  /// Existing values are NOT overwritten — `overwrite: 0`.
  private static func prepareHuggingFaceEnvironment() {
    let cache = PathProvider.modelCacheDirectory.path
    let cacheParent = PathProvider.modelCacheDirectory
      .deletingLastPathComponent().path
    let xdgCache = URL.cachesDirectory.path
    try? FileManager.default.createDirectory(
      at: PathProvider.modelCacheDirectory,
      withIntermediateDirectories: true
    )
    setenv("HF_HUB_CACHE", cache, 1)
    setIfUnset("HF_HOME", cacheParent)
    setIfUnset("TRANSFORMERS_CACHE", cache)
    setIfUnset("XDG_CACHE_HOME", xdgCache)
    setIfUnset("HF_TOKEN", "")
    setIfUnset("HUGGING_FACE_HUB_TOKEN", "")
    setIfUnset("HUGGINGFACE_HUB_TOKEN", "")
    setIfUnset("HOME", NSHomeDirectory())
    setIfUnset("USER", "mobile")
    setIfUnset("LOGNAME", "mobile")
    Logger.log("HuggingFace env prepared (cache=\(cache))")
  }

  private static func setIfUnset(_ key: String, _ value: String) {
    if ProcessInfo.processInfo.environment[key] == nil {
      setenv(key, value, 1)
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView(store: store)
    }
  }
}
