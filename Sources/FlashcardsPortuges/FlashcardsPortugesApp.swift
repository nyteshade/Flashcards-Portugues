import AppKit
import SwiftUI

@main
struct FlashcardsPortugesApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var store = DictionaryStore()
  @ObservedObject private var translator = EuroLLMTranslator.shared
  
  init() {
    Logger.log("FlashcardsPortugesApp started.")
    EuroLLMTranslator.shared.autoLoadIfCached()
    AppDelegate.sharedStore = store
  }
  
  var body: some Scene {
    WindowGroup {
      ContentView(store: store)
    }
    .handlesExternalEvents(matching: [])
    .windowResizability(.contentSize)
    .commands {
      CommandGroup(replacing: .newItem) {
        // Suppress the default New menu item so cmd-N doesn't
        // spawn a second blank window. Single-instance app —
        // file opens are handled by AppDelegate.application(_:openURLs:).
      }
    }
    
    Settings {
      SettingsView(translator: translator)
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  nonisolated(unsafe) static weak var sharedStore: DictionaryStore?
  
  func application(_ application: NSApplication, open urls: [URL]) {
    guard let store = Self.sharedStore else { return }
    for url in urls {
      Logger.log("Opening file: \(url.path)")
      do {
        let deck = try DeckIO.read(from: url)
        store.adoptDeck(deck, makeActive: true)
      } catch {
        Logger.log("Failed to open \(url.lastPathComponent): \(error.localizedDescription)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not open \"\(url.lastPathComponent)\""
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
      }
    }
  }
}
