import SwiftUI

struct TranslateView: View {
    @ObservedObject var store: DictionaryStore
    @ObservedObject private var translator = EuroLLMTranslator.shared

    @State private var input: String = ""

    @State private var result: LLMTranslation?
    @State private var detectedDirection: LLMDirection?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Translate")
                    .font(.title2)
                    .padding(.bottom, 4)

                Text("Type English or Portuguese — EuroLLM detects the language and translates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                inputRow

                if let error = error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                if let result = result, let direction = detectedDirection {
                    resultBlock(result: result, direction: direction)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var inputRow: some View {
        HStack(alignment: .top, spacing: 8) {
            TextEditor(text: $input)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                )

            VStack(spacing: 6) {
                Button(action: runTranslate) {
                    if busy {
                        ProgressView().controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .frame(width: 28, height: 28)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Translate with EuroLLM (⌘↵)")

                Button(action: speakInput) {
                    Image(systemName: "speaker.wave.2")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Speak — American English or European Portuguese based on detected language")

                Spacer()
            }

            // Hidden buttons just to own keyboard shortcuts. cmd-enter
            // anywhere in the tab triggers translate.
            ZStack {
                Button(action: runTranslate) { EmptyView() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0)
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func resultBlock(result: LLMTranslation, direction: LLMDirection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(directionLabel(direction))
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)

            snippetRow(
                label: "Direct",
                text: result.translation.direct,
                pairedText: pairedTextForResult(otherSide: result.translation.direct, direction: direction)
            )
            snippetRow(
                label: "Colloquial",
                text: result.translation.colloquial,
                pairedText: pairedTextForResult(otherSide: result.translation.colloquial, direction: direction)
            )

            if let examples = result.translation.relatedExamples, !examples.isEmpty {
                Divider()
                Text("Related Examples")
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(examples) { example in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(example.portuguese)
                                    .font(.body)
                                    .textSelection(.enabled)
                                Text(example.english)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            TranslationActionsView(
                                store: store,
                                portuguese: example.portuguese,
                                english: example.english,
                                partOfSpeech: .phrase
                            )
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(0.4))
        )
    }

    private func directionLabel(_ direction: LLMDirection) -> String {
        switch direction {
        case .englishToPortuguese: return "Detected: English → Portuguese"
        case .portugueseToEnglish: return "Detected: Portuguese → English"
        }
    }

    @ViewBuilder
    private func snippetRow(label: String, text: String, pairedText: (portuguese: String, english: String)) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                Text(text.isEmpty ? "—" : text)
                    .textSelection(.enabled)
            }
            Spacer()
            if !text.isEmpty,
               !pairedText.portuguese.isEmpty,
               !pairedText.english.isEmpty {
                TranslationActionsView(
                    store: store,
                    portuguese: pairedText.portuguese,
                    english: pairedText.english,
                    partOfSpeech: .phrase
                )
            }
        }
    }

    /// Map a translation snippet to the (portuguese, english) pair we
    /// hand to the actions row so add-to-deck makes sense.
    private func pairedTextForResult(otherSide translated: String, direction: LLMDirection) -> (portuguese: String, english: String) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch direction {
        case .englishToPortuguese:
            return (portuguese: translated, english: trimmedInput)
        case .portugueseToEnglish:
            return (portuguese: trimmedInput, english: translated)
        }
    }

    /// Speak the current input. If a translation result is showing,
    /// use the SLM-detected language; otherwise heuristic-detect from
    /// Portuguese-specific characters and default to English.
    private func speakInput() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let language = detectedLanguageForInput(trimmed)
        SpeechService.speak(trimmed, language: language)
    }

    private func detectedLanguageForInput(_ text: String) -> SpeechService.Language {
        // Prefer the SLM's classification if the user has already
        // translated this text — most accurate signal we have.
        if let direction = detectedDirection {
            switch direction {
            case .englishToPortuguese: return .englishUS
            case .portugueseToEnglish: return .portuguese
            }
        }
        // No translation yet. Heuristic: any Portuguese-characteristic
        // diacritic flips us to PT. English doesn't use these.
        let portugueseSignals: Set<Character> = ["ã", "õ", "â", "ê", "ô", "ç", "á", "í", "ó", "ú", "à"]
        for ch in text.lowercased() where portugueseSignals.contains(ch) {
            return .portuguese
        }
        return .englishUS
    }

    private func runTranslate() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        busy = true
        error = nil

        Task {
            defer { Task { @MainActor in busy = false } }
            do {
                let outcome = try await translator.autoTranslate(trimmed)
                await MainActor.run {
                    result = outcome.translation
                    detectedDirection = outcome.direction
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.result = nil
                    self.detectedDirection = nil
                }
            }
        }
    }
}
