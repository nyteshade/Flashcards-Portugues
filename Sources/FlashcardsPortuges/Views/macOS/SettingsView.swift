import AVFoundation
import SwiftUI

struct SettingsView: View {
  @ObservedObject var translator: EuroLLMTranslator
  @ObservedObject private var voicePrefs = VoicePreferences.shared

  /// User's choice of default variant. `"auto"` or a `ModelVariant.id`.
  /// `EuroLLMTranslator.autoLoadIfCached` reads the same key.
  @AppStorage(ModelCatalog.activeVariantDefaultsKey) private var activeVariantPref: String = "auto"

  @State private var loadTask: Task<Void, Never>?
  @State private var warningVariant: ModelVariant?
  /// Bumped after delete/download completion so the catalog rows
  /// re-render their on-disk state without needing a separate
  /// FileManager observer.
  @State private var cacheToken: Int = 0
  /// Bumped to force the voice pickers to re-query AVSpeechSynthesisVoice
  /// after the user clicks "Refresh voices" — useful when they download
  /// new ones from System Settings while the app is already running.
  @State private var voicesReloadToken = 0

  private let physicalRAMBytes = DeviceRAM.physical

  var body: some View {
    Form {
      Section {
        defaultVariantPicker
        Divider()
        ForEach(ModelCatalog.all) { variant in
          variantRow(variant)
          if variant.id != ModelCatalog.all.last?.id {
            Divider()
          }
        }
      } header: {
        Text("Translation Model").font(.headline)
      } footer: {
        Text("EuroLLM powers translation, chat, and learning hints. Larger variants give better answers but need more RAM; Auto picks the largest downloaded variant that fits comfortably on this machine.")
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
    .frame(width: 620, height: 640)
    .navigationTitle("Settings")
    .sheet(item: $warningVariant) { variant in
      ramWarningSheet(for: variant)
    }
  }

  // MARK: - Default variant picker

  @ViewBuilder
  private var defaultVariantPicker: some View {
    let onDisk = ModelCatalog.onDiskVariants()
    HStack {
      Text("Default")
      Spacer()
      Picker("Default", selection: $activeVariantPref) {
        Text("Auto").tag("auto")
        ForEach(onDisk) { variant in
          Text(variant.displayName).tag(variant.id)
        }
      }
      .labelsHidden()
      .frame(maxWidth: 320)
      .disabled(onDisk.isEmpty)
    }
    .help(onDisk.isEmpty
          ? "Download a variant first to enable selection"
          : "Auto picks the largest downloaded variant that fits comfortably on this Mac")
  }

  // MARK: - Variant row

  @ViewBuilder
  private func variantRow(_ variant: ModelVariant) -> some View {
    let isPending = translator.pendingVariant?.id == variant.id
    let onDisk = !isPending && isOnDisk(variant)
    let isActive = !isPending && translator.activeVariant?.id == variant.id
    let recommended = ModelCatalog.recommended(physicalRAMBytes: physicalRAMBytes)

    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(variant.displayName).font(.body)
          if recommended?.variant.id == variant.id {
            Text("Recommended")
              .font(.caption2)
              .padding(.horizontal, 6).padding(.vertical, 2)
              .background(Color.accentColor.opacity(0.15))
              .foregroundStyle(Color.accentColor)
              .cornerRadius(4)
          }
        }
        Text("\(variant.parameterScale.rawValue) · \(variant.quant.rawValue) · \(variant.sizeOnDiskHint)")
          .font(.caption)
          .foregroundStyle(.secondary)
        if isPending {
          pendingStatusLine
        } else if isActive {
          activeStatusLine
        }
      }

      Spacer(minLength: 8)

      variantButtons(
        variant: variant,
        onDisk: onDisk,
        isActive: isActive,
        isPending: isPending
      )
    }
    .padding(.vertical, 4)
    .id("variant-\(variant.id)-\(cacheToken)")
  }

  @ViewBuilder
  private func variantButtons(
    variant: ModelVariant,
    onDisk: Bool,
    isActive: Bool,
    isPending: Bool
  ) -> some View {
    if isPending {
      Button(role: .destructive) {
        cancelLoad()
      } label: {
        Label("Cancel", systemImage: "xmark.circle")
      }
      .buttonStyle(.bordered)
    } else if !onDisk {
      Button {
        attemptLoad(variant)
      } label: {
        Label("Download", systemImage: "arrow.down.circle")
      }
      .buttonStyle(.bordered)
      .disabled(loadInFlight)
    } else if isActive {
      Button {
        ejectActive()
      } label: {
        Label("Eject", systemImage: "stop.circle")
      }
      .buttonStyle(.bordered)
      .disabled(loadInFlight)

      Button(role: .destructive) {
        deleteVariant(variant)
      } label: {
        Label("Delete", systemImage: "trash")
      }
      .disabled(loadInFlight)
    } else {
      Button {
        attemptLoad(variant)
      } label: {
        Label("Load", systemImage: "play.circle")
      }
      .buttonStyle(.borderedProminent)
      .disabled(loadInFlight)

      Button(role: .destructive) {
        deleteVariant(variant)
      } label: {
        Label("Delete", systemImage: "trash")
      }
      .disabled(loadInFlight)
    }
  }

  @ViewBuilder
  private var pendingStatusLine: some View {
    HStack(spacing: 6) {
      ProgressView().controlSize(.small)
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
  private var activeStatusLine: some View {
    HStack(spacing: 6) {
      ModelStatusPill(translator: translator)
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

  // MARK: - Warning sheet

  @ViewBuilder
  private func ramWarningSheet(for variant: ModelVariant) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Insufficient RAM", systemImage: "exclamationmark.triangle.fill")
        .font(.headline)
        .foregroundStyle(.orange)
      Text("\(variant.displayName) is estimated to need ~\(humanGB(variant.estimatedBytes)) of RAM. This Mac has ~\(humanGB(physicalRAMBytes)).")
        .font(.body)
      Text("Loading anyway may fail outright, page heavily, or destabilize other apps. A smaller variant will run more reliably.")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        Button("Cancel") {
          warningVariant = nil
        }
        .keyboardShortcut(.escape)
        Spacer()
        Button("Continue anyway") {
          let variant = variant
          warningVariant = nil
          forceLoad(variant)
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(20)
    .frame(width: 420)
  }

  // MARK: - Voice section (unchanged)

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

  // MARK: - Helpers

  private var loadInFlight: Bool {
    if case .loading = translator.status { return true }
    return false
  }

  private func isOnDisk(_ variant: ModelVariant) -> Bool {
    // Re-read each render; the cacheToken in `.id(...)` invalidates
    // the row after a download/delete completes.
    ModelCatalog.isOnDisk(variant)
  }

  private func humanGB(_ bytes: Int) -> String {
    String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
  }

  private func attemptLoad(_ variant: ModelVariant) {
    loadTask?.cancel()
    loadTask = Task {
      do {
        try await translator.load(variant: variant)
      } catch MLXTranslatorError.harnessRejection {
        await MainActor.run { warningVariant = variant }
      } catch {
        Logger.log("Load failed for \(variant.id): \(error.localizedDescription)")
      }
      await MainActor.run { cacheToken &+= 1 }
    }
  }

  private func forceLoad(_ variant: ModelVariant) {
    loadTask?.cancel()
    loadTask = Task {
      do {
        try await translator.forceLoad(variant: variant)
      } catch {
        Logger.log("Force-load failed for \(variant.id): \(error.localizedDescription)")
      }
      await MainActor.run { cacheToken &+= 1 }
    }
  }

  private func ejectActive() {
    loadTask?.cancel()
    loadTask = Task {
      await translator.unload()
      await MainActor.run { cacheToken &+= 1 }
    }
  }

  private func deleteVariant(_ variant: ModelVariant) {
    loadTask?.cancel()
    loadTask = Task {
      await translator.delete(variant: variant)
      await MainActor.run { cacheToken &+= 1 }
    }
  }

  private func cancelLoad() {
    loadTask?.cancel()
    loadTask = nil
  }
}
