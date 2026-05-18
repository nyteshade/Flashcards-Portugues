import Foundation

/// Single source of truth for the app's on-disk storage roots.
///
/// Resolves paths identically whether the app is sandboxed or not, and
/// identically on macOS or iOS — so the eventual iOS target inherits
/// correct storage locations with zero path-handling changes.
///
/// HuggingFace cache resolution now lives in MLXModelKit's
/// `ModelCacheProvider.defaultCacheDirectory`.
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
}
