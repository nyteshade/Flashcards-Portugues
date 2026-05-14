import Foundation
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

/// Glue between the app and the host OS file dialogs. On macOS this
/// drives `NSSavePanel` / `NSOpenPanel`; an iOS target will need
/// `UIDocumentPicker`-backed implementations behind the same surface.
/// The symbol is present on both platforms so callers compile
/// unchanged; iOS bodies are no-op stubs until that target is wired up.
@MainActor
enum DeckFileService {
  /// Prompt for a save location and write the deck as a `.flcd`.
  /// macOS: stamps the file with the bundled `StudyDeck.icns` so it
  /// shows the deck icon in Finder.
  static func saveDeckAs(_ deck: Deck) {
    #if os(macOS)
    let panel = NSSavePanel()
    panel.title = "Save Deck"
    panel.nameFieldStringValue = "\(deck.name).\(DeckDocument.fileExtension)"
    panel.allowedContentTypes = [Self.flcdType]
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try DeckIO.write(deck: deck, to: url)
      applyDeckIcon(to: url)
    } catch {
      presentError(title: "Could not save deck", error: error)
    }
    #else
    Logger.log("DeckFileService.saveDeckAs: not implemented on this platform")
    #endif
  }

  /// Prompt for a `.flcd` file and return the decoded deck.
  static func openDeck() -> Deck? {
    #if os(macOS)
    let panel = NSOpenPanel()
    panel.title = "Open Deck"
    panel.allowedContentTypes = [Self.flcdType, .json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    do {
      return try DeckIO.read(from: url)
    } catch {
      presentError(title: "Could not open deck", error: error)
      return nil
    }
    #else
    Logger.log("DeckFileService.openDeck: not implemented on this platform")
    return nil
    #endif
  }

  /// Prompt for a destination and write a Markdown rendering of `deck`.
  static func exportDeckAsMarkdown(_ deck: Deck) {
    #if os(macOS)
    let panel = NSSavePanel()
    panel.title = "Export Deck as Markdown"
    panel.nameFieldStringValue = "\(deck.name).md"
    panel.allowedContentTypes = [.plainText]
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let markdown = DeckIO.markdown(for: deck)
    do {
      try markdown.data(using: .utf8)?.write(to: url, options: .atomic)
    } catch {
      presentError(title: "Could not export deck", error: error)
    }
    #else
    Logger.log("DeckFileService.exportDeckAsMarkdown: not implemented on this platform")
    #endif
  }

  // MARK: - File type

  /// `.flcd` UTType. Cross-platform — `UTType` is in
  /// UniformTypeIdentifiers, available on iOS too.
  static var flcdType: UTType {
    UTType(filenameExtension: DeckDocument.fileExtension, conformingTo: .json) ?? .json
  }

  #if os(macOS)
  // MARK: - macOS-only helpers

  /// Apply the bundled StudyDeck icon as a custom Finder icon on
  /// `url`. No-op if the icon resource isn't present in the bundle.
  /// Failures here are non-fatal — the file is already saved; the
  /// icon is cosmetic.
  private static func applyDeckIcon(to url: URL) {
    guard let iconURL = Bundle.main.url(forResource: "StudyDeck", withExtension: "icns"),
          let icon = NSImage(contentsOf: iconURL) else {
      return
    }
    NSWorkspace.shared.setIcon(icon, forFile: url.path, options: [])
  }

  private static func presentError(title: String, error: Error) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
  #endif
}
