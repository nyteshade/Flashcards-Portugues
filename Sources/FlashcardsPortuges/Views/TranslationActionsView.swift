import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Compact icon-button row that appears next to a translation snippet.
/// Three actions: copy to clipboard, pronounce, add to study deck.
/// Pronunciation always pronounces the Portuguese side.
struct TranslationActionsView: View {
  @ObservedObject var store: DictionaryStore
  let portuguese: String
  let english: String
  let partOfSpeech: PartOfSpeech
  
  /// Which side the user is *seeing* — drives which string the
  /// copy button picks up. Pronunciation stays Portuguese either way.
  enum CopyTarget { case portuguese, english, both }
  var copyTarget: CopyTarget = .portuguese
  
  @State private var copied = false
  @State private var added = false
  
  var body: some View {
    HStack(spacing: 10) {
      Button(action: copy) {
        Image(systemName: copied ? "checkmark" : "doc.on.doc")
          .font(.body)
      }
      .buttonStyle(.borderless)
      .help("Copy to clipboard")
      
      Button {
        SpeechService.speak(portuguese)
      } label: {
        Image(systemName: "speaker.wave.2")
          .font(.body)
      }
      .buttonStyle(.borderless)
      .help("Pronounce (European Portuguese)")
      
      Button(action: addToDeck) {
        Image(systemName: added ? "checkmark.seal.fill" : "plus.rectangle.on.rectangle")
          .font(.body)
          .foregroundColor(added ? .green : .accentColor)
      }
      .buttonStyle(.borderless)
      .disabled(added || portuguese.isEmpty || english.isEmpty)
      .help(added ? "Added to study deck" : "Add to study deck")
    }
    .onAppear {
      added = store.studyDeck.cards.contains {
        !$0.isVerbCard && $0.portuguese == portuguese
      }
    }
  }
  
  private func copy() {
    let text: String
    switch copyTarget {
    case .portuguese: text = portuguese
    case .english: text = english
    case .both: text = "\(portuguese) — \(english)"
    }
    #if os(macOS)
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
    #elseif os(iOS)
    UIPasteboard.general.string = text
    #endif
    copied = true
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.2))
      copied = false
    }
  }
  
  private func addToDeck() {
    guard !portuguese.isEmpty, !english.isEmpty else { return }
    // Use the existing entry-creation path so dictionary + deck stay in sync.
    store.addEntry(portuguese: portuguese, english: english, partOfSpeech: partOfSpeech)
    if let entry = store.entries.last {
      store.addToStudyDeck(entry: entry)
    }
    added = true
  }
}
