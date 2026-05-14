import Foundation

/// The inference slice of `EuroLLMTranslator` that ViewModels depend
/// on. ViewModels hold `any LLMTranslating` so they can be unit-tested
/// with a stub translator returning canned `LLMTranslation` /
/// `LLMDefinition` values.
///
/// This deliberately excludes the variant-management surface
/// (load/forceLoad/delete/activeVariant/pendingVariant/status). Only
/// `SettingsView` + `ModelStatusPill` touch those, and they keep the
/// concrete `EuroLLMTranslator` because they observe its `@Published`
/// state directly via `@ObservedObject`.
@MainActor
protocol LLMTranslating: AnyObject {
  var isReady: Bool { get }

  func translate(_ text: String, direction: LLMDirection) async throws -> LLMTranslation
  func autoTranslate(_ text: String) async throws -> (translation: LLMTranslation, direction: LLMDirection)
  func chat(prompt: String, maxTokens: Int) async throws -> String
  func defineWithExamples(portuguese: String) async throws -> LLMDefinition
  func portugueseInfinitive(forEnglish: String) async -> String?
}

extension LLMTranslating {
  /// Convenience matching `EuroLLMTranslator.chat`'s defaulted
  /// `maxTokens` — protocol requirements can't carry default values.
  func chat(prompt: String) async throws -> String {
    try await chat(prompt: prompt, maxTokens: 1024)
  }
}
