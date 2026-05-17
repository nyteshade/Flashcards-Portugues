import AVFoundation
import SwiftUI

/// iPadOS Settings — presented as a sheet from ContentView's gear
/// button. Mirrors the iOS SettingsView layout with iPad-appropriate
/// sizing. Model catalog, voice picker, and load/delete controls.
struct SettingsView: View {
  @ObservedObject var translator: EuroLLMTranslator
  @ObservedObject private var voicePrefs = VoicePreferences.shared
  @AppStorage(ModelCatalog.activeVariantDefaultsKey)
  private var activeVariantPref: String = "auto"

  @Environment(\.dismiss) private var dismiss
  @State private var loadTask: Task<Void, Never>?
  @State private var warningVariant: ModelVariant?
  @State private var cacheToken: Int = 0
  @State private var loadErrorMessage: String?
  @State private var voicesReloadToken = 0

  private let physicalRAMBytes = DeviceRAM.physical

  private var isSimulator: Bool {
    #if targetEnvironment(simulator)
    return true
    #else
    return false
    #endif
  }

  var body: some View {
    NavigationStack {
      List {
        if isSimulator {
          Section {
            Label {
              VStack(alignment: .leading, spacing: 4) {
                Text("Simulator can't run MLX")
                  .font(.subheadline.weight(.semibold))
                Text("Downloads and on-device translation/chat require a real iPad. The Simulator's Metal backend can't initialize MLX.")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            }
            .padding(.vertical, 4)
          }
        }

        Section {
          defaultVariantPicker
          ForEach(ModelCatalog.all) { variant in
            variantRow(variant)
          }
        } header: {
          Text("Translation Model")
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
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $warningVariant) { variant in
        ramWarningSheet(for: variant)
      }
    }
    .frame(minWidth: 480, idealWidth: 560, minHeight: 500)
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
    let isActive = !isPending
      && translator.activeVariant?.id == variant.id
    let recommended = ModelCatalog.recommended(
      physicalRAMBytes: physicalRAMBytes
    )

    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text(variant.displayName).font(.body)
        if recommended?.variant.id == variant.id {
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

      HStack(spacing: 12) {
        if isPending {
          ProgressView().controlSize(.small)
          Button("Cancel", role: .destructive) { cancelLoad() }
        } else if !onDisk {
          Button("Download") { attemptLoad(variant) }
            .disabled(loadInFlight)
        } else if isActive {
          Button("Eject") { ejectActive() }
            .disabled(loadInFlight)
          Button("Delete", role: .destructive) {
            deleteVariant(variant)
          }
          .disabled(loadInFlight)
        } else {
          Button("Load") { attemptLoad(variant) }
            .buttonStyle(.borderedProminent)
            .disabled(loadInFlight)
          Button("Delete", role: .destructive) {
            deleteVariant(variant)
          }
          .disabled(loadInFlight)
        }
      }
      .buttonStyle(.bordered)
    }
    .padding(.vertical, 4)
    .id("variant-\(variant.id)-\(cacheToken)")
  }

  // MARK: - Warning sheet

  @ViewBuilder
  private func ramWarningSheet(for variant: ModelVariant) -> some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        Label("Insufficient RAM",
              systemImage: "exclamationmark.triangle.fill")
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
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { warningVariant = nil }
        }
        ToolbarItem(placement: .primaryAction) {
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
        SpeechService.speak(
          sampleSentence(for: language), language: language
        )
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

  private func sampleSentence(
    for language: SpeechService.Language
  ) -> String {
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
        await MainActor.run {
          loadErrorMessage = error.localizedDescription
        }
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
        await MainActor.run {
          loadErrorMessage = error.localizedDescription
        }
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
