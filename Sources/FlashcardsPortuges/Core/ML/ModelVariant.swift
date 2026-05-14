import Foundation

/// One selectable EuroLLM model variant. Drives both `EuroLLMTranslator`
/// load decisions and the Settings model picker. Keep this struct flat
/// so the catalog stays readable.
struct ModelVariant: Identifiable, Hashable {
  enum Quant: String {
    case fourBit = "4-bit"
    case bfloat16 = "bf16"
  }

  enum ParameterScale: String {
    case b1_7 = "1.7B"
    case b9 = "9B"
    case b22 = "22B"
  }

  /// Stable identifier used in `@AppStorage`, MLX coordinator routing,
  /// and on-disk lookups. Format: `eurollm-<scale>-instruct-<quant>`.
  let id: String

  /// Human-readable label for Settings, e.g. "EuroLLM 9B Instruct (4-bit)".
  let displayName: String

  /// HuggingFace repo path, e.g. `stelterlab/EuroLLM-9B-Instruct-MLX-4bit`.
  let huggingFaceRepo: String

  let quant: Quant
  let parameterScale: ParameterScale

  /// Approximate resident bytes after load. Used by the harness
  /// admission check and by `ModelCatalog.recommended` to decide which
  /// variant fits comfortably on the current machine.
  let estimatedBytes: Int

  /// Short on-disk size hint shown in the picker, e.g. "~5.4 GB".
  let sizeOnDiskHint: String

  /// HuggingFace hub cache directory for this variant — used to check
  /// "is it downloaded yet?" and to delete cached weights. Rooted at
  /// `PathProvider.modelCacheDirectory` so it tracks the App Sandbox
  /// container automatically.
  var cacheDir: URL {
    let parts = huggingFaceRepo.split(separator: "/")
    let folder: String
    if parts.count == 2 {
      folder = "models--\(parts[0])--\(parts[1])"
    } else {
      folder = "models--\(huggingFaceRepo.replacingOccurrences(of: "/", with: "--"))"
    }
    return PathProvider.modelCacheDirectory.appendingPathComponent(folder)
  }
}
