import SwiftUI

/// iPadOS Translate tab. Single-pane with large TextEditor,
/// Translate button, and results area. Uses the wider iPad canvas
/// for side-by-side source/translation display.
struct TranslateView: View {
  @StateObject private var viewModel = TranslateViewModel()

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          inputArea
          translateButton
          if let result = viewModel.result {
            resultArea(result: result)
          }
          if viewModel.busy {
            ProgressView("Translating…")
          }
          if let error = viewModel.error {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
        .padding()
        .frame(maxWidth: 700)
      }
      .navigationTitle("Translate")
    }
  }

  @ViewBuilder
  private var inputArea: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Enter text")
        .font(.caption)
        .foregroundStyle(.secondary)
      TextEditor(text: $viewModel.input)
        .font(.body)
        .frame(minHeight: 120)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
        )
    }
  }

  @ViewBuilder
  private var translateButton: some View {
    HStack {
      Button {
        viewModel.runTranslate()
      } label: {
        Label("Translate", systemImage: "globe")
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.borderedProminent)
      .disabled(
        viewModel.input.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty || viewModel.busy
      )

      Button {
        SpeechService.speak(
          viewModel.input.trimmingCharacters(
            in: .whitespacesAndNewlines
          )
        )
      } label: {
        Image(systemName: "speaker.wave.2")
          .frame(minHeight: 44)
      }
      .buttonStyle(.bordered)
      .disabled(
        viewModel.input.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty
      )
    }
  }

  @ViewBuilder
  private func resultArea(result: LLMTranslation) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Divider()

      HStack {
        Text("Direct Translation")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          SpeechService.speak(result.translation.direct)
        } label: {
          Image(systemName: "speaker.wave.2")
        }
        .buttonStyle(.borderless)
      }
      Text(result.translation.direct)
        .font(.body)

      if !result.translation.colloquial.isEmpty
          && result.translation.colloquial
            != result.translation.direct {
        HStack {
          Text("Colloquial")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button {
            SpeechService.speak(result.translation.colloquial)
          } label: {
            Image(systemName: "speaker.wave.2")
          }
          .buttonStyle(.borderless)
        }
        Text(result.translation.colloquial)
          .font(.body)
          .foregroundStyle(.secondary)
      }
    }
  }
}
