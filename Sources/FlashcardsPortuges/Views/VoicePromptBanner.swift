import SwiftUI

/// Slim top-of-window banner nudging the user to install an
/// Enhanced/Premium pt-PT voice. Driven by `VoicePromptViewModel`;
/// the parent view decides whether to render it (banner doesn't
/// gate itself — caller checks `viewModel.shouldShow`).
struct VoicePromptBanner: View {
  @ObservedObject var viewModel: VoicePromptViewModel

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: "speaker.wave.2.bubble")
        .font(.system(size: 18))
        .foregroundStyle(Color.accentColor)

      VStack(alignment: .leading, spacing: 2) {
        Text("Get a more natural Portuguese voice")
          .font(.system(size: 13, weight: .medium))
        Text("Sofia sounds much better with the Enhanced or Premium pt-PT voice. Free, installed from System Settings.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      Button("Open Settings") {
        viewModel.openSettings()
      }
      .controlSize(.small)
      .buttonStyle(.borderedProminent)

      Button("Not now") {
        viewModel.snooze()
      }
      .controlSize(.small)
      .buttonStyle(.bordered)

      Button {
        viewModel.dismissPermanently()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
      .help("Don't ask again")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.accentColor.opacity(0.10))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
    )
    .padding(.horizontal, 12)
    .padding(.top, 8)
  }
}
