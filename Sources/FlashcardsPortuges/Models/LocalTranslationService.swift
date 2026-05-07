import Foundation

/// Thin async wrapper that routes through `EuroLLMTranslator`. Kept
/// as the same `enum` shape callers were already using so existing
/// call sites only need to switch to the `async` API.
enum LocalTranslationService {
    /// Returns the parsed JSON translation. Direction is inferred
    /// from the language pair: `pt`->`en` uses portugueseToEnglish,
    /// anything else uses englishToPortuguese.
    static func translate(
        text: String,
        from fromLang: String = "pt-PT",
        to toLang: String = "en-GB"
    ) async throws -> LLMTranslation {
        let direction: LLMDirection =
            fromLang.lowercased().hasPrefix("pt") ? .portugueseToEnglish : .englishToPortuguese
        return try await EuroLLMTranslator.shared.translate(text, direction: direction)
    }
}
