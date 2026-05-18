import Foundation
import MLXModelKit

/// Loads LLM prompt templates from the app bundle and substitutes
/// `{{name}}` placeholders with runtime values.
///
/// Prompts live at `Resources/Prompts/<scale>/<name>.md` where
/// `<scale>` is one of `1.7B`, `9B`, `22B`, or `default`. Lookup tries
/// the active variant's scale first and falls back to `default` —
/// this means only prompts that need per-model tuning need a copy in
/// the scale-specific folder. See `Resources/Prompts/README.md` for
/// the full convention.
///
/// `currentScale` is set by `EuroLLMTranslator` when a variant loads.
/// Default is `.b9` — what the baseline prompts were tuned against.
enum PromptLoader {
  /// Currently-active model scale. Updated by `EuroLLMTranslator`
  /// every time a variant becomes the loaded variant. Reads default
  /// to the 9B path until the first load resolves.
  nonisolated(unsafe) static var currentScale: ModelVariant.ParameterScale = .b9

  /// Load `name.md` (no extension in the argument), substitute
  /// `{{key}}` placeholders from `vars`, and return the rendered
  /// prompt. Fatal-errors if neither the scale-specific nor the
  /// default file exists in the bundle — those are dev mistakes,
  /// not runtime conditions.
  static func load(_ name: String, vars: [String: String] = [:]) -> String {
    let raw = readTemplate(name)
    var rendered = raw
    for (key, value) in vars {
      rendered = rendered.replacingOccurrences(of: "{{\(key)}}", with: value)
    }
    return rendered
  }

  private static func readTemplate(_ name: String) -> String {
    let scale = currentScale.rawValue
    if let url = Bundle.main.url(
      forResource: name,
      withExtension: "md",
      subdirectory: "Prompts/\(scale)"
    ),
       let body = try? String(contentsOf: url, encoding: .utf8) {
      return body
    }
    if let url = Bundle.main.url(
      forResource: name,
      withExtension: "md",
      subdirectory: "Prompts/default"
    ),
       let body = try? String(contentsOf: url, encoding: .utf8) {
      return body
    }
    fatalError("PromptLoader: no '\(name).md' found in Prompts/\(scale)/ or Prompts/default/")
  }
}
