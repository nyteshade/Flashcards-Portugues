import SwiftUI

/// Single button that picks the best available translator. Spyglass
/// when only the local dictionary is available (single-word lookup);
/// wand when EuroLLM is loaded (full phrase translation, returns
/// `direct` and `colloquial` variants).
///
/// Pressing on the EN-adjacent field translates EN → PT and writes the
/// colloquial (or direct as fallback) into the PT field. Pressing on
/// the PT-adjacent field does the reverse.
struct SmartTranslateButton: View {
    enum Side { case english, portuguese }

    @Binding var portuguese: String
    @Binding var english: String
    let side: Side
    @Binding var status: String
    @Binding var partOfSpeech: PartOfSpeech

    @ObservedObject private var translator = EuroLLMTranslator.shared
    @State private var isWorking = false

    var body: some View {
        Button(action: run) {
            if isWorking {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: useLLM ? "wand.and.stars" : "magnifyingglass")
            }
        }
        .help(helpText)
        .disabled(isWorking || sourceText.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var useLLM: Bool { translator.isReady }

    private var helpText: String {
        if useLLM {
            return side == .english
                ? "Translate English → Portuguese with EuroLLM"
                : "Translate Portuguese → English with EuroLLM"
        } else {
            return side == .english
                ? "Look up English in local dictionary"
                : "Look up Portuguese in local dictionary"
        }
    }

    private var sourceText: String {
        side == .english ? english : portuguese
    }

    private func run() {
        let text = sourceText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        if useLLM {
            isWorking = true
            status = "Translating with EuroLLM…"
            Task {
                defer { Task { @MainActor in isWorking = false } }
                do {
                    let direction: LLMDirection = side == .english
                        ? .englishToPortuguese
                        : .portugueseToEnglish
                    let result = try await translator.translate(text, direction: direction)
                    await MainActor.run {
                        let preferred = result.translation.colloquial.isEmpty
                            ? result.translation.direct
                            : result.translation.colloquial
                        if side == .english {
                            portuguese = preferred
                        } else {
                            english = preferred
                        }
                        status = "✓ Translated (colloquial)"
                    }
                    // Classify POS off the Portuguese side regardless of direction.
                    let portugueseTextForPOS = side == .english
                        ? (result.translation.colloquial.isEmpty
                           ? result.translation.direct
                           : result.translation.colloquial)
                        : text
                    if let pos = await translator.classifyPartOfSpeech(portuguese: portugueseTextForPOS) {
                        await MainActor.run {
                            partOfSpeech = pos
                            status = "✓ Translated · \(pos.rawValue)"
                        }
                    }
                } catch {
                    await MainActor.run {
                        status = "Translation failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            // Fallback: local single-word dictionary lookup (no POS detection)
            let from = side == .english ? "en" : "pt"
            let to = side == .english ? "pt" : "en"
            if let result = DictionaryLookup.dictionaryTranslate(text, from: from, to: to) {
                if side == .english {
                    portuguese = result
                } else {
                    english = result
                }
                status = "✓ Found in dictionary"
            } else {
                status = "Not in dictionary"
            }
        }
    }
}
