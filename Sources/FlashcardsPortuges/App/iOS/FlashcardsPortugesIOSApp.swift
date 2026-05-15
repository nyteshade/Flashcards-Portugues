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
    EuroLLMTranslator.shared.autoLoadIfCached()
  }

  /// Pre-populate the HuggingFace hub env vars so the C++ side of
  /// MLX / swift-transformers always has a non-null `getenv` result
  /// when it constructs `std::string`. The download crash on iOS
  /// surfaces as `_LIBCPP_ASSERT_NON_NULL(__s != nullptr,
  /// "basic_string(const char*) detected nullptr")` — libc++ catching
  /// a `getenv("HF_HUB_CACHE")` returning NULL because iOS apps don't
  /// inherit the user's shell environment. Setting these here makes
  /// PathProvider's cache path the authoritative location on iOS too.
  private static func prepareHuggingFaceEnvironment() {
    let cache = PathProvider.modelCacheDirectory.path
    try? FileManager.default.createDirectory(
      at: PathProvider.modelCacheDirectory,
      withIntermediateDirectories: true
    )
    setenv("HF_HUB_CACHE", cache, 1)
    if ProcessInfo.processInfo.environment["HF_HOME"] == nil {
      setenv("HF_HOME", PathProvider.modelCacheDirectory.deletingLastPathComponent().path, 1)
    }
    Logger.log("HuggingFace cache prepared at \(cache)")
  }

  var body: some Scene {
    WindowGroup {
      ContentView(store: store)
    }
  }
}
