import AVFoundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var translator: EuroLLMTranslator
    @ObservedObject private var voicePrefs = VoicePreferences.shared
    @State private var loadTask: Task<Void, Never>?
    /// Bumped to force the voice pickers to re-query AVSpeechSynthesisVoice
    /// after the user clicks "Refresh voices" — useful when they download
    /// new ones from System Settings while the app is already running.
    @State private var voicesReloadToken = 0

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(EuroLLMTranslator.huggingFaceRepo)
                        .font(.system(.body, design: .monospaced))
                    Text("4-bit MLX quantization · ~5.4 GB on disk · Apple Silicon required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                statusRow
                actionRow
            } header: {
                Text("Translation Model").font(.headline)
            } footer: {
                Text("EuroLLM powers phrase translation and learning hints. The first download is large; subsequent launches reuse the cached weights.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                voicePicker(
                    title: "American English",
                    language: .englishUS,
                    selection: $voicePrefs.englishUSVoiceID
                )
                .id("en-\(voicesReloadToken)")

                voicePicker(
                    title: "European Portuguese",
                    language: .portuguese,
                    selection: $voicePrefs.portugueseVoiceID
                )
                .id("pt-\(voicesReloadToken)")

                HStack {
                    Spacer()
                    Button {
                        voicesReloadToken += 1
                    } label: {
                        Label("Refresh voices", systemImage: "arrow.clockwise")
                    }
                    .help("Re-scan installed system voices")
                }
            } header: {
                Text("Voices").font(.headline)
            } footer: {
                Text("Premium and Enhanced voices sound more natural. Download more in System Settings → Accessibility → Spoken Content → System Voice → Manage Voices…\nIf a freshly-downloaded voice isn't showing, click Refresh voices, or restart the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 540)
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack {
            ModelStatusPill(translator: translator)
            Spacer()
            Text(translator.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }

        if case .loading(let fraction) = translator.status {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            switch translator.status {
            case .notLoaded, .failed:
                if EuroLLMTranslator.isModelOnDisk() {
                    Button {
                        startDownload()
                    } label: {
                        Label("Load", systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        deleteModel()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } else {
                    Button {
                        startDownload()
                    } label: {
                        Label("Download & Load", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .loading:
                Button("Cancel", role: .destructive) {
                    loadTask?.cancel()
                    loadTask = nil
                }
            case .ready, .processing:
                Button {
                    unloadModel()
                } label: {
                    Label("Unload", systemImage: "stop.circle")
                }

                Button(role: .destructive) {
                    deleteModel()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func voicePicker(title: String, language: SpeechService.Language, selection: Binding<String>) -> some View {
        let voices = VoicePreferences.availableVoices(for: language)
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: selection) {
                ForEach(voices, id: \.identifier) { voice in
                    Text(voiceLabel(voice)).tag(voice.identifier)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 280)

            Button {
                let sample = sampleSentence(for: language)
                SpeechService.speak(sample, language: language)
            } label: {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.bordered)
            .help("Preview")
            .disabled(voices.isEmpty)
        }
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        var label = voice.name
        if voice.quality != .default {
            label += " · \(voice.qualityLabel)"
        }
        if !voice.language.isEmpty {
            label += "  (\(voice.language))"
        }
        return label
    }

    private func sampleSentence(for language: SpeechService.Language) -> String {
        switch language {
        case .englishUS:
            return "Hello, this is a quick voice preview."
        case .portuguese:
            return "Olá, esta é uma rápida amostra de voz."
        }
    }

    private func startDownload() {
        loadTask?.cancel()
        loadTask = Task {
            do {
                try await translator.ensureLoaded()
            } catch {
                Logger.log("Download/load failed from Settings: \(error.localizedDescription)")
            }
        }
    }

    private func unloadModel() {
        loadTask?.cancel()
        loadTask = Task {
            await translator.unload()
        }
    }

    private func deleteModel() {
        loadTask?.cancel()
        loadTask = Task {
            await translator.deleteCachedModel()
        }
    }
}
