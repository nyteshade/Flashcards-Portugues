import SwiftUI

struct TranslateView: View {
  @ObservedObject var store: DictionaryStore
  @StateObject private var viewModel = TranslateViewModel()

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

        if let error = viewModel.error {
          Text(error)
            .font(.callout)
            .foregroundStyle(.red)
        }

        if let result = viewModel.result, let direction = viewModel.detectedDirection {
          resultBlock(result: result, direction: direction)
        }
      }
      .padding(20)
    }
  }

  @ViewBuilder
  private var inputRow: some View {
    HStack(alignment: .top, spacing: 8) {
      TextEditor(text: $viewModel.input)
        .font(.body)
        .frame(minHeight: 100, maxHeight: 160)
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
        )

      VStack(spacing: 6) {
        Button { viewModel.runTranslate() } label: {
          if viewModel.busy {
            ProgressView().controlSize(.small)
              .frame(width: 28, height: 28)
          } else {
            Image(systemName: "wand.and.stars")
              .frame(width: 28, height: 28)
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.busy || viewModel.input.trimmingCharacters(in: .whitespaces).isEmpty)
        .help("Translate with EuroLLM (⌘↵)")

        Button { viewModel.speakInput() } label: {
          Image(systemName: "speaker.wave.2")
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.input.trimmingCharacters(in: .whitespaces).isEmpty)
        .help("Speak — defaults to European Portuguese; switches to American English only when high-confidence English")

        Spacer()
      }

      // Hidden buttons just to own keyboard shortcuts. cmd-enter
      // anywhere in the tab triggers translate.
      ZStack {
        Button { viewModel.runTranslate() } label: { EmptyView() }
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
}
