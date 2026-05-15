import AVFoundation
import SwiftUI

/// iOS-shaped settings — a pushed `NavigationStack` presented as a
/// sheet from `ContentView`'s gear button. Same model-catalog + voice
/// management as the macOS `Settings { }` scene, just in a List rather
/// than a Form-window layout.
struct SettingsView: View {
  @ObservedObject var translator: EuroLLMTranslator
  @ObservedObject private var voicePrefs = VoicePreferences.shared
  @AppStorage(ModelCatalog.activeVariantDefaultsKey) private var activeVariantPref: String = "auto"

  @Environment(\.dismiss) private var dismiss
  @State private var loadTask: Task<Void, Never>?
  @State private var warningVariant: ModelVariant?
  /// Bumped after delete/download completion so the catalog rows
  /// re-read their on-disk state without a separate FileManager
  /// observer.
  @State private var cacheToken: Int = 0
  /// Bumped to force the voice pickers to re-query
  /// AVSpeechSynthesisVoice after the user taps "Refresh voices".
  @State private var voicesReloadToken = 0

  private let physicalRAMBytes = Int(ProcessInfo.processInfo.physicalMemory)

  var body: some View {
    NavigationStack {
      List {
        Section {
          defaultVariantPicker
          ForEach(ModelCatalog.all) { variant in
            variantRow(variant)
          }
        } header: {
          Text("Translation Model")
        } footer: {
          Text("EuroLLM powers translation, chat, and learning hints. Larger variants give better answers but need more RAM; Auto picks the largest downloaded variant that fits comfortably on this device.")
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

          Button {
            voicesReloadToken += 1
          } label: {
            Label("Refresh voices", systemImage: "arrow.clockwise")
          }
        } header: {
          Text("Voices")
        } footer: {
          Text("Premium and Enhanced voices sound more natural. iOS bundles many; if a freshly-downloaded voice isn't showing, tap Refresh voices, or relaunch the app.")
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $warningVariant) { variant in
        ramWarningSheet(for: variant)
      }
    }
  }

  // MARK: - Default variant picker

  @ViewBuilder
  private var defaultVariantPicker: some View {
    let onDisk = ModelCatalog.onDiskVariants()
    Picker("Default", selection: $activeVariantPref) {
      Text("Auto").tag("auto")
      ForEach(onDisk) { variant in
        Text(variant.displayName).tag(variant.id)
      }
    }
    .disabled(onDisk.isEmpty)
  }

  // MARK: - Variant row

  @ViewBuilder
  private func variantRow(_ variant: ModelVariant) -> some View {
    let isPending = translator.pendingVariant?.id == variant.id
    let onDisk = !isPending && ModelCatalog.isOnDisk(variant)
    let isActive = !isPending && translator.activeVariant?.id == variant.id
    let recommended = ModelCatalog.recommended(physicalRAMBytes: physicalRAMBytes)

    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text(variant.displayName).font(.body)
        if recommended?.id == variant.id {
          Text("Recommended")
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
        }
        Spacer()
      }
      Text("\(variant.parameterScale.rawValue) · \(variant.quant.rawValue) · \(variant.sizeOnDiskHint)")
        .font(.caption)
        .foregroundStyle(.secondary)

      if isPending {
        pendingStatusLine
      } else if isActive {
        activeStatusLine
      }

      HStack(spacing: 12) {
        variantButtons(variant: variant, onDisk: onDisk, isActive: isActive, isPending: isPending)
      }
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
      .buttonStyle(.bordered)
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
      .buttonStyle(.bordered)
      .disabled(loadInFlight)
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
    }
  }

  // MARK: - Warning sheet

  @ViewBuilder
  private func ramWarningSheet(for variant: ModelVariant) -> some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        Label("Insufficient RAM", systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
          .foregroundStyle(.orange)
        Text("\(variant.displayName) is estimated to need ~\(humanGB(variant.estimatedBytes)) of RAM. This device has ~\(humanGB(physicalRAMBytes)).")
          .font(.body)
        Text("Loading anyway may fail outright or page heavily. A smaller variant will run more reliably.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
      }
      .padding()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { warningVariant = nil }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Continue") {
            let v = variant
            warningVariant = nil
            forceLoad(v)
          }
        }
      }
    }
    .presentationDetents([.medium])
  }

  // MARK: - Voice picker

  @ViewBuilder
  private func voicePicker(
    title: String,
    language: SpeechService.Language,
    selection: Binding<String>
  ) -> some View {
    let voices = VoicePreferences.availableVoices(for: language)
    HStack {
      Picker(title, selection: selection) {
        ForEach(voices, id: \.identifier) { voice in
          Text(voiceLabel(voice)).tag(voice.identifier)
        }
      }
      Button {
        let sample = sampleSentence(for: language)
        SpeechService.speak(sample, language: language)
      } label: {
        Image(systemName: "speaker.wave.2")
      }
      .buttonStyle(.borderless)
      .disabled(voices.isEmpty)
    }
  }

  private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
    var label = voice.name
    if voice.quality != .default {
      label += " · \(voice.qualityLabel)"
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
