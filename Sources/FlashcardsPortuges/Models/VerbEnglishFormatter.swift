import Foundation

/// Normalizes English verb translations so they always read as
/// infinitives. EuroLLM occasionally drops the leading "to" when
/// translating a Portuguese infinitive on its own (`ser` → "be"
/// instead of "to be"), which reads oddly next to the Portuguese
/// infinitive. This helper restores the prefix when it's missing.
enum VerbEnglishFormatter {
  /// Words that should NOT receive a "to " prefix even when they
  /// look like a single bare token — they're already nominal /
  /// adjectival glosses the model returned for non-verb inputs.
  /// Empty for now; placeholder for future tuning.
  private static let skipPrefix: Set<String> = []
  
  static func normalize(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }
    let lower = trimmed.lowercased()
    if lower.hasPrefix("to ") { return trimmed }
    if skipPrefix.contains(lower) { return trimmed }
    return "to " + trimmed
  }
}
