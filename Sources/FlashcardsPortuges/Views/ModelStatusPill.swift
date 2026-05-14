import SwiftUI

struct ModelStatusPill: View {
  @ObservedObject var translator: EuroLLMTranslator
  
  var body: some View {
    HStack(spacing: 6) {
      indicator
      Text(label)
        .font(.body)
        .foregroundStyle(.primary)
        .lineLimit(1)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 5)
    .help(translator.statusMessage)
  }
  
  @ViewBuilder
  private var indicator: some View {
    switch translator.status {
    case .notLoaded:
      Circle()
        .fill(.secondary)
        .frame(width: 8, height: 8)
    case .loading(let fraction):
      ZStack {
        Circle()
          .stroke(.tertiary, lineWidth: 1.5)
          .frame(width: 10, height: 10)
        Circle()
          .trim(from: 0, to: max(0.05, fraction))
          .stroke(.orange, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
          .frame(width: 10, height: 10)
          .rotationEffect(.degrees(-90))
      }
    case .ready:
      Circle()
        .fill(.green)
        .frame(width: 8, height: 8)
    case .processing:
      Circle()
        .fill(.green)
        .frame(width: 8, height: 8)
        .modifier(PulseModifier())
    case .failed:
      Circle()
        .fill(.red)
        .frame(width: 8, height: 8)
    }
  }
  
  private var label: String {
    let tag: String = {
      if let v = translator.activeVariant {
        return "EuroLLM-\(v.parameterScale.rawValue)"
      }
      if let p = translator.pendingVariant {
        return "EuroLLM-\(p.parameterScale.rawValue)"
      }
      return "EuroLLM"
    }()
    switch translator.status {
    case .notLoaded:
      return "\(tag): not loaded"
    case .loading(let fraction):
      return "\(tag): loading \(Int(fraction * 100))%"
    case .ready:
      return "\(tag): ready"
    case .processing:
      return "\(tag): processing…"
    case .failed:
      return "\(tag): failed"
    }
  }
}

private struct PulseModifier: ViewModifier {
  @State private var pulsing = false
  func body(content: Content) -> some View {
    content
      .opacity(pulsing ? 0.3 : 1.0)
      .animation(
        .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
        value: pulsing
      )
      .onAppear { pulsing = true }
      .onDisappear { pulsing = false }
  }
}
