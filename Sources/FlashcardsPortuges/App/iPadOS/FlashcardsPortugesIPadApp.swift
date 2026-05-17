import AVFoundation
import Darwin
import SwiftUI

/// iPadOS app entry point. Mirrors iOS app startup but targets the
/// iPad-only target (TARGETED_DEVICE_FAMILY=2). Uses Views/iPadOS/
/// for all view content — no shared views with iPhone or macOS.
@main
struct FlashcardsPortugesIPadApp: App {
  @StateObject private var store = DictionaryStore()

  init() {
    Logger.log("FlashcardsPortugesIPadApp started.")
    Self.prepareHuggingFaceEnvironment()
    Self.prepareAudioSession()
    EuroLLMTranslator.shared.autoLoadIfCached()
  }

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
