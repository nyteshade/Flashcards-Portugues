import Foundation

/// All EuroLLM variants the app knows about, plus helpers for
/// on-disk detection and "best fit" recommendation. The catalog is
/// the single source of truth — Settings UI, autoLoad routing, and
/// the translator all consult it.
enum ModelCatalog {
  static let all: [ModelVariant] = [
    ModelVariant(
      id: "eurollm-1.7b-instruct-4bit",
      displayName: "EuroLLM 1.7B Instruct (4-bit)",
      // Community-uploaded MLX 4-bit quantization. mlx-community
      // itself only publishes 22B variants for EuroLLM as of 2026-05.
      huggingFaceRepo: "dreamer1cc/EuroLLM-1.7B-Instruct-4bit",
      quant: .fourBit,
      parameterScale: .b1_7,
      estimatedBytes: Int(1.5 * 1024 * 1024 * 1024),
      sizeOnDiskHint: "~1.0 GB"
    ),
    ModelVariant(
      id: "eurollm-1.7b-instruct-bf16",
      displayName: "EuroLLM 1.7B Instruct (bf16)",
      // No mlx-community bf16 1.7B exists; we route to the original
      // HF transformers safetensors. swift-transformers' auto-loader
      // converts on the fly.
      huggingFaceRepo: "utter-project/EuroLLM-1.7B-Instruct",
      quant: .bfloat16,
      parameterScale: .b1_7,
      estimatedBytes: Int(4.0 * 1024 * 1024 * 1024),
      sizeOnDiskHint: "~3.4 GB"
    ),
    ModelVariant(
      id: "eurollm-9b-instruct-mlx-4bit",
      displayName: "EuroLLM 9B Instruct (4-bit)",
      huggingFaceRepo: "stelterlab/EuroLLM-9B-Instruct-MLX-4bit",
      quant: .fourBit,
      parameterScale: .b9,
      estimatedBytes: 6 * 1024 * 1024 * 1024,
      sizeOnDiskHint: "~5.4 GB"
    ),
    ModelVariant(
      id: "eurollm-22b-instruct-2512-mlx-4bit",
      displayName: "EuroLLM 22B Instruct (4-bit)",
      huggingFaceRepo: "mlx-community/EuroLLM-22B-Instruct-2512-mlx-4bit",
      quant: .fourBit,
      parameterScale: .b22,
      estimatedBytes: 14 * 1024 * 1024 * 1024,
      sizeOnDiskHint: "~13 GB"
    ),
  ]

  static func find(id: String) -> ModelVariant? {
    all.first(where: { $0.id == id })
  }

  /// True iff the variant's HuggingFace cache directory exists and
  /// contains at least one snapshot — the same loose check the
  /// original single-model `isModelOnDisk()` used.
  static func isOnDisk(_ variant: ModelVariant) -> Bool {
    let snapshots = variant.cacheDir.appendingPathComponent("snapshots")
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: snapshots.path, isDirectory: &isDir),
          isDir.boolValue else { return false }
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: snapshots.path)) ?? []
    return !contents.isEmpty
  }

  static func onDiskVariants() -> [ModelVariant] {
    all.filter(isOnDisk)
  }

  /// "Best quality that fits comfortably": from `candidates` (default:
  /// the full catalog), pick the variant with the largest
  /// `estimatedBytes` whose `estimatedBytes + headroom <=
  /// physicalRAMBytes`. Headroom is `min(25 % of RAM, 8 GB)`. If
  /// nothing fits, fall back to the smallest candidate so the picker
  /// always badges *something* when there's any choice at all.
  static func recommended(
    physicalRAMBytes: Int,
    among candidates: [ModelVariant]? = nil
  ) -> ModelVariant? {
    let pool = candidates ?? all
    guard !pool.isEmpty else { return nil }
    let headroom = min(
      Int(Double(physicalRAMBytes) * 0.25),
      8 * 1024 * 1024 * 1024
    )
    let fits = pool.filter { $0.estimatedBytes + headroom <= physicalRAMBytes }
    if let best = fits.max(by: { $0.estimatedBytes < $1.estimatedBytes }) {
      return best
    }
    return pool.min(by: { $0.estimatedBytes < $1.estimatedBytes })
  }

  /// Resolve a persisted preference ("auto" or a variant id) to a
  /// concrete variant *that exists on disk*. Used by autoLoadIfCached
  /// and by translate/chat call paths' lazy `ensureLoaded`. Returns
  /// nil when the user picked Auto but nothing is downloaded, or when
  /// the named variant has been deleted from disk.
  static func resolveActive(
    preference: String,
    physicalRAMBytes: Int
  ) -> ModelVariant? {
    if preference == "auto" {
      let disk = onDiskVariants()
      guard !disk.isEmpty else { return nil }
      return recommended(physicalRAMBytes: physicalRAMBytes, among: disk)
    }
    guard let variant = find(id: preference), isOnDisk(variant) else {
      return nil
    }
    return variant
  }

  /// Stable UserDefaults / `@AppStorage` key for the user's chosen
  /// default. Value is either `"auto"` or a `ModelVariant.id`.
  static let activeVariantDefaultsKey = "eurollm_active_variant"
}
