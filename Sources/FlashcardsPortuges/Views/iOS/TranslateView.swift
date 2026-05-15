import SwiftUI

/// iOS-native Translate tab. Full-width `TextEditor` input at the top
/// with the prominent "Translate" CTA below it (iOS users expect the
/// primary action in content, not buried in the nav bar). Speak is a
/// secondary icon button next to the CTA. Results scroll below.
/// Reuses `TranslateViewModel` and the shared `TranslationActionsView`
/// (which already #if-branches NSPasteboard for iOS).
struct TranslateView: View {
  @ObservedObject var store: DictionaryStore
  @Binding var showSettings: Bool
  @StateObject private var viewModel = TranslateViewModel()
  @FocusState private var inputFocused: Bool

  init(store: DictionaryStore, showSettings: Binding<Bool>) {
    self.store = store
    self._showSettings = showSettings
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Type English or Portuguese — EuroLLM detects the language and translates.")
            .font(.caption)
            .foregroundStyle(.secondary)

          inputArea
          actionRow

          if let error = viewModel.error {
            Text(error)
              .font(.callout)
              .foregroundStyle(.red)
          }

          if let result = viewModel.result, let direction = viewModel.detectedDirection {
            resultBlock(result: result, direction: direction)
          }
        }
        .padding()
      }
      .navigationTitle("Translate")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.visible, for: .tabBar)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { showSettings = true } label: {
            Image(systemName: "gearshape")
          }
        }
      }
    }
  }

  @ViewBuilder
  private var inputArea: some View {
    TextEditor(text: $viewModel.input)
      .focused($inputFocused)
      .font(.body)
      .frame(minHeight: 120, maxHeight: 220)
      .padding(8)
      .background(Color.gray.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
      )
      .autocorrectionDisabled()
  }

  @ViewBuilder
  private var actionRow: some View {
    HStack(spacing: 12) {
      Button {
        inputFocused = false
        viewModel.runTranslate()
      } label: {
        HStack {
          if viewModel.busy {
            ProgressView().tint(.white).controlSize(.small)
          } else {
            Image(systemName: "wand.and.stars")
          }
          Text("Translate")
        }
        .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.busy ||
                viewModel.input.trimmingCharacters(in: .whitespaces).isEmpty)

      Button { viewModel.speakInput() } label: {
        Image(systemName: "speaker.wave.2")
          .font(.title3)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.bordered)
      .disabled(viewModel.input.trimmingCharacters(in: .whitespaces).isEmpty)
      .accessibilityLabel("Speak")
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
        pairedText: viewModel.pairedTextForResult(otherSide: result.translation.direct, direction: direction)
      )
      snippetRow(
        label: "Colloquial",
        text: result.translation.colloquial,
        pairedText: viewModel.pairedTextForResult(otherSide: result.translation.colloquial, direction: direction)
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
      RoundedRectangle(cornerRadius: 8)
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
}
