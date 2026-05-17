import Foundation

/// iOS / iPadOS device model identifier → physical RAM (bytes).
/// Used as a fallback when ProcessInfo reports the host Mac's RAM on
/// the simulator, and as a cross-check on real devices.
///
/// Sources: Apple spec sheets, Geekbench teardowns, everymac.com.
/// Devices not listed here fall back to ProcessInfo (real device) or
/// a conservative 6 GB estimate (simulator).
enum DeviceRAM {

  /// Known device RAM in bytes, keyed by `hw.model` (e.g. "iPhone18,1").
  /// Sorted roughly newest → oldest within each family.
  private static let table: [String: Int] = {
    let gb = 1_073_741_824
    return [
      // MARK: iPhones
      "iPhone18,1": 12 * gb,  // iPhone 17 Pro Max
      "iPhone18,2": 12 * gb,  // iPhone 17 Pro
      "iPhone18,3": 11 * gb,  // iPhone 17 Air (11.5 → 11)
      "iPhone18,4":  8 * gb,  // iPhone 17
      "iPhone17,5":  8 * gb,  // iPhone 17e
      "iPhone17,1":  8 * gb,  // iPhone 16 Pro Max
      "iPhone17,2":  8 * gb,  // iPhone 16 Pro
      "iPhone17,3":  8 * gb,  // iPhone 16
      "iPhone17,4":  8 * gb,  // iPhone 16 Plus
      "iPhone16,1":  8 * gb,  // iPhone 15 Pro Max
      "iPhone16,2":  8 * gb,  // iPhone 15 Pro
      "iPhone15,4":  6 * gb,  // iPhone 15
      "iPhone15,5":  6 * gb,  // iPhone 15 Plus
      "iPhone15,2":  6 * gb,  // iPhone 14 Pro Max
      "iPhone15,3":  6 * gb,  // iPhone 14 Pro
      "iPhone14,7":  6 * gb,  // iPhone 14
      "iPhone14,8":  6 * gb,  // iPhone 14 Plus
      "iPhone14,2":  6 * gb,  // iPhone 13 Pro Max
      "iPhone14,3":  6 * gb,  // iPhone 13 Pro
      "iPhone14,4":  4 * gb,  // iPhone 13 mini
      "iPhone14,5":  4 * gb,  // iPhone 13
      "iPhone14,6":  4 * gb,  // iPhone SE (3rd gen)
      "iPhone13,2":  6 * gb,  // iPhone 12 Pro Max
      "iPhone13,3":  6 * gb,  // iPhone 12 Pro
      "iPhone13,1":  4 * gb,  // iPhone 12 mini
      "iPhone13,4":  4 * gb,  // iPhone 12
      "iPhone12,8":  4 * gb,  // iPhone SE (2nd gen)
      "iPhone12,1":  4 * gb,  // iPhone 11
      "iPhone12,3":  4 * gb,  // iPhone 11 Pro
      "iPhone12,5":  4 * gb,  // iPhone 11 Pro Max

      // MARK: iPads (M-series + A-series)
      "iPad16,3": 16 * gb,  // iPad Pro 13" M5
      "iPad16,4": 16 * gb,  // iPad Pro 13" M5 (WiFi+Cellular)
      "iPad16,5": 12 * gb,  // iPad Pro 11" M5
      "iPad16,6": 12 * gb,  // iPad Pro 11" M5 (WiFi+Cellular)
      "iPad16,1":  8 * gb,  // iPad Air M4 13"
      "iPad16,2":  8 * gb,  // iPad Air M4 11"
      "iPad14,8": 16 * gb,  // iPad Pro 13" M4
      "iPad14,9": 16 * gb,  // iPad Pro 13" M4 (WiFi+Cellular)
      "iPad14,3":  8 * gb,  // iPad Pro 11" M4
      "iPad14,4":  8 * gb,  // iPad Pro 11" M4 (WiFi+Cellular)
      "iPad14,10": 8 * gb,  // iPad Air M2 13"
      "iPad14,11": 8 * gb,  // iPad Air M2 13" (WiFi+Cellular)
      "iPad13,18": 8 * gb,  // iPad Pro 12.9" M2
      "iPad13,19": 8 * gb,  // iPad Pro 12.9" M2 (WiFi+Cellular)
      "iPad13,20": 8 * gb,  // iPad Pro 11" M2
      "iPad13,21": 8 * gb,  // iPad Pro 11" M2 (WiFi+Cellular)
      "iPad13,16": 8 * gb,  // iPad Air M1
      "iPad13,17": 8 * gb,  // iPad Air M1 (WiFi+Cellular)
      "iPad13,8":  16 * gb,  // iPad Pro 12.9" M1 (16 GB SKU)
      "iPad13,9":  16 * gb,  // iPad Pro 12.9" M1 (16 GB SKU, Cellular)
      "iPad13,4":   8 * gb,  // iPad Pro 11" M1
      "iPad13,5":   8 * gb,  // iPad Pro 11" M1 (WiFi+Cellular)
      "iPad13,10":  8 * gb,  // iPad Pro 12.9" M1 (8 GB SKU)
      "iPad13,11":  8 * gb,  // iPad Pro 12.9" M1 (8 GB SKU, Cellular)
    ]
  }()

  /// Best available physical RAM for this device in bytes.
  ///
  /// On real devices `ProcessInfo.processInfo.physicalMemory` is
  /// accurate. On the iOS Simulator it reports the host Mac's RAM,
  /// so we fall back to the device-model table. If the model isn't
  /// recognized on simulator, we assume 6 GB (the iPhone-midpoint)
  /// so recommendations are conservative rather than wildly wrong.
  static var physical: Int {
    #if os(iOS) && targetEnvironment(simulator)
    return ramForModel(modelIdentifier(), fallback: 6 * 1_073_741_824)
    #else
    let reported = Int(ProcessInfo.processInfo.physicalMemory)
    // On macOS, ProcessInfo is always correct. On real iOS devices
    // it's correct too — cross-check with the table only for a log.
    return reported
    #endif
  }

  /// The device model identifier from `sysctl hw.model`.
  /// Returns e.g. "iPhone18,1" or "Mac16,7".
  static func modelIdentifier() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var model = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &model, &size, nil, 0)
    return String(cString: model)
  }

  /// Look up known RAM for `model`. Returns nil if unrecognized.
  static func ramForModel(_ model: String) -> Int? {
    table[model]
  }

  /// Look up known RAM for `model` with a caller-supplied fallback.
  static func ramForModel(_ model: String, fallback: Int) -> Int {
    table[model] ?? fallback
  }
}

/// Result of `ModelCatalog.recommended(…)` — the best variant for
/// this device plus a budget-fit assessment. The UI can use
/// `fitWarning` to show a caution banner; the user can override and
/// load any variant regardless of the warning.
struct ModelRecommendation {
  let variant: ModelVariant
  let fitWarning: FitWarning?
  let deviceRAMBytes: Int

  enum FitWarning: String {
    /// Variant fits with comfortable headroom. No warning.
    case none
    /// Variant fits but leaves little room for other processes.
    /// On iOS this means the app is at risk of jetsam if another
    /// memory-heavy app is in the background.
    case tight
    /// Estimated resident bytes exceed the device's physical RAM.
    /// The OS may kill the process during load. Proceed at your
    /// own risk — `forceLoad` path is available.
    case exceedsRAM
  }
}

/// All EuroLLM variants the app knows about, plus helpers for
/// on-disk detection and "best fit" recommendation. The catalog is
/// the single source of truth — Settings UI, autoLoad routing, and
/// the translator all consult it.
enum ModelCatalog {
  static let all: [ModelVariant] = [
    ModelVariant(
      id: "eurollm-1.7b-instruct-4bit",
      displayName: "EuroLLM 1.7B Instruct (4-bit)",
      huggingFaceRepo: "dreamer1cc/EuroLLM-1.7B-Instruct-4bit",
      quant: .fourBit,
      parameterScale: .b1_7,
      estimatedBytes: Int(1.5 * 1024 * 1024 * 1024),
      sizeOnDiskHint: "~1.0 GB"
    ),
    ModelVariant(
      id: "eurollm-1.7b-instruct-bf16",
      displayName: "EuroLLM 1.7B Instruct (bf16)",
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

  static func isOnDisk(_ variant: ModelVariant) -> Bool {
    let snapshots = variant.cacheDir
      .appendingPathComponent("snapshots")
    var isDir: ObjCBool = false

    guard FileManager.default.fileExists(
      atPath: snapshots.path, isDirectory: &isDir
    ),
          isDir.boolValue
    else { return false }

    let contents = (try? FileManager.default
      .contentsOfDirectory(atPath: snapshots.path)) ?? []

    return !contents.isEmpty
  }

  static func onDiskVariants() -> [ModelVariant] {
    all.filter(isOnDisk)
  }

  /// "Best quality that fits": from `candidates` (default: the full
  /// catalog), pick the variant with the largest `estimatedBytes`
  /// whose `estimatedBytes + headroom <= physicalRAMBytes`.
  ///
  /// Headroom is `min(25 % of RAM, 8 GB)`. If nothing fits, fall
  /// back to the smallest candidate so the picker always badges
  /// *something* when there's any choice at all.
  ///
  /// No variant is ever excluded — the recommendation always returns
  /// the best-fit variant, but the `fitWarning` field tells the UI
  /// whether to show a caution. Use `forceLoad` to override.
  static func recommended(
    physicalRAMBytes: Int,
    among candidates: [ModelVariant]? = nil
  ) -> ModelRecommendation? {
    let pool = candidates ?? all

    guard !pool.isEmpty else { return nil }

    let headroom = min(
      Int(Double(physicalRAMBytes) * 0.25),
      8 * 1024 * 1024 * 1024
    )

    let fits = pool.filter {
      $0.estimatedBytes + headroom <= physicalRAMBytes
    }

    if let best = fits.max(by: { $0.estimatedBytes < $1.estimatedBytes })
    {
      return ModelRecommendation(
        variant: best,
        fitWarning: .none,
        deviceRAMBytes: physicalRAMBytes
      )
    }

    // Nothing fits comfortably. Return the smallest variant with a
    // warning — the user can still load it via forceLoad.
    let smallest = pool.min(by: {
      $0.estimatedBytes < $1.estimatedBytes
    })!

    let warning: ModelRecommendation.FitWarning =
      smallest.estimatedBytes > physicalRAMBytes
        ? .exceedsRAM
        : .tight

    return ModelRecommendation(
      variant: smallest,
      fitWarning: warning,
      deviceRAMBytes: physicalRAMBytes
    )
  }

  /// Resolve a persisted preference ("auto" or a variant id) to a
  /// concrete variant *that exists on disk*. Used by
  /// `autoLoadIfCached` and by translate/chat call paths' lazy
  /// `ensureLoaded`.
  static func resolveActive(
    preference: String,
    physicalRAMBytes: Int
  ) -> ModelVariant? {
    if preference == "auto" {
      let disk = onDiskVariants()

      guard !disk.isEmpty else { return nil }

      return recommended(
        physicalRAMBytes: physicalRAMBytes, among: disk
      )?.variant
    }

    guard let variant = find(id: preference), isOnDisk(variant)
    else { return nil }

    return variant
  }

  /// Stable UserDefaults / `@AppStorage` key for the user's chosen
  /// default. Value is either `"auto"` or a `ModelVariant.id`.
  static let activeVariantDefaultsKey = "eurollm_active_variant"
}
