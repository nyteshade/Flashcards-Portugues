import AppKit
import SwiftUI

@main
struct FlashcardsPortugesApp: App {
    @StateObject private var store = DictionaryStore()
    @ObservedObject private var translator = EuroLLMTranslator.shared

    init() {
        Logger.log("FlashcardsPortugesApp started.")
        EuroLLMTranslator.shared.autoLoadIfCached()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .onOpenURL { url in
                    handleOpen(url: url)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Suppress the default New / Open behaviour from
                // WindowGroup so cmd-N doesn't spawn a second blank
                // window. Single-instance app — file opens reuse this
                // window via .onOpenURL.
            }
        }

        Settings {
            SettingsView(translator: translator)
        }
    }

    @MainActor
    private func handleOpen(url: URL) {
        Logger.log("Opening file: \(url.path)")
        do {
            let deck = try DeckIO.read(from: url)
            store.adoptDeck(deck, makeActive: true)
        } catch {
            Logger.log("Failed to open \(url.lastPathComponent): \(error.localizedDescription)")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not open “\(url.lastPathComponent)”"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
