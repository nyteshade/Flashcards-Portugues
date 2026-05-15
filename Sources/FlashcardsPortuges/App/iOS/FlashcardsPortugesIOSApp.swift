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
    EuroLLMTranslator.shared.autoLoadIfCached()
  }

  var body: some Scene {
    WindowGroup {
      ContentView(store: store)
    }
  }
}
