import Foundation

/// Single source of truth for the app's on-disk storage roots.
///
/// Resolves paths identically whether the app is sandboxed or not, and
/// identically on macOS or iOS — so the eventual iOS target inherits
/// correct storage locations with zero path-handling changes.
///
/// **The model-cache resolution deliberately mirrors swift-huggingface's
/// `CacheLocationProvider.defaultCacheDirectory`** (HF_HUB_CACHE →
/// HF_HOME/hub → sandbox-aware default). The library auto-detects the
/// App Sandbox via `APP_SANDBOX_CONTAINER_ID` and relocates its cache
/// into the container; our `ModelCatalog.isOnDisk` check must look in
/// the same place. If these two ever drift, the app would download to
/// one directory and check another. Keep them in lockstep.
enum PathProvider {
  /// `<Application Support>/FlashcardsPortuges`, created on access.
  /// Under the App Sandbox this auto-resolves into the app container;
  /// unsandboxed it's user-domain Application Support.
  static var appSupportDirectory: URL {
    let base = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!
      .appendingPathComponent("FlashcardsPortuges", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: base, withIntermediateDirectories: true
    )
    return base
  }

  /// HuggingFace hub cache root — the directory that holds the
  /// `models--<owner>--<repo>` folders. Mirrors swift-huggingface's
  /// resolution so our on-disk checks match where the library writes.
  static var modelCacheDirectory: URL {
    let env = ProcessInfo.processInfo.environment

    // 1. HF_HUB_CACHE — explicit override, used verbatim.
    if let hubCache = env["HF_HUB_CACHE"], !hubCache.isEmpty {
      return URL(fileURLWithPath: (hubCache as NSString).expandingTildeInPath)
    }
    // 2. HF_HOME + /hub
    if let hfHome = env["HF_HOME"], !hfHome.isEmpty {
      return URL(fileURLWithPath: (hfHome as NSString).expandingTildeInPath)
        .appendingPathComponent("hub")
    }
    // 3. Sandbox-aware default.
    #if os(macOS)
    let isSandboxed = env["APP_SANDBOX_CONTAINER_ID"] != nil
    if isSandboxed {
      return URL.cachesDirectory
        .appendingPathComponent("huggingface")
        .appendingPathComponent("hub")
    }
    return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      .appendingPathComponent(".cache")
      .appendingPathComponent("huggingface")
      .appendingPathComponent("hub")
    #else
    return URL.cachesDirectory
      .appendingPathComponent("huggingface")
      .appendingPathComponent("hub")
    #endif
  }
}
