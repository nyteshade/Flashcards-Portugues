import SwiftUI

/// Popover content for the Study tab's Define button. Shows the SLM
/// definition + example sentences when available, otherwise falls
/// back to the local dictionary entry.
struct DefinePopover: View {
  let word: String
  let llmResult: LLMDefinition?
  let llmBusy: Bool
  let llmError: String?
  let dictionaryFallback: String?
  let onClose: () -> Void
  
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(word).font(.headline)
        if let pos = llmResult?.partOfSpeech, !pos.isEmpty {
          Text(pos)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.gray.opacity(0.18))
            .cornerRadius(4)
        }
        Spacer()
        Button {
          SpeechService.speak(word)
        } label: {
          Image(systemName: "speaker.wave.2")
        }
        .buttonStyle(.borderless)
        .help("Pronounce")
      }
      
      Divider()
      
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if llmBusy && llmResult == nil {
            HStack(spacing: 6) {
              ProgressView().controlSize(.small)
              Text("Defining with EuroLLM…")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          
          if let result = llmResult {
            Text(result.definition)
              .font(.body)
              .textSelection(.enabled)
            
            if !result.examples.isEmpty {
              Text("Examples")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .padding(.top, 4)
              VStack(alignment: .leading, spacing: 8) {
                ForEach(result.examples) { example in
                  HStack(alignment: .top, spacing: 6) {
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
                    Button {
                      SpeechService.speak(example.portuguese)
                    } label: {
                      Image(systemName: "speaker.wave.2")
                        .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Pronounce example")
                  }
                }
              }
            }
          }
          
          if llmResult == nil, let fallback = dictionaryFallback {
            Text(fallback)
              .font(.body)
              .textSelection(.enabled)
          }
          
          if llmResult == nil, dictionaryFallback == nil, !llmBusy {
            Text("No definition found.")
              .font(.body)
              .foregroundStyle(.secondary)
          }
          
          if let error = llmError {
            Text("EuroLLM error: \(error)")
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
      }
      .frame(maxHeight: 280)
      
      HStack {
        Spacer()
        Button("Close", action: onClose)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding()
    .frame(width: 380)
  }
}
