import Foundation
import MLXLMCommon

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

  func translate(
    _ text: String, direction: LLMDirection
  ) async throws -> LLMTranslation
  func autoTranslate(
    _ text: String
  ) async throws -> (translation: LLMTranslation, direction: LLMDirection)

  /// Multi-turn chat with structured Chat.Message. MLX-LM applies
  /// the model's chat template (ChatML for EuroLLM) automatically.
  /// The first message must be `.system`; subsequent messages
  /// alternate `.user` / `.assistant`.
  func chat(messages: [Chat.Message], maxTokens: Int) async throws -> String

  /// Raw-string chat — kept for backward compat with callers that
  /// still build a flat prompt. Prefer `chat(messages:)` when you
  /// have structured role data.
  func chat(prompt: String, maxTokens: Int) async throws -> String

  func defineWithExamples(
    portuguese: String) async throws -> LLMDefinition
  func portugueseInfinitive(forEnglish: String) async -> String?
}

extension LLMTranslating {
  /// Convenience — default maxTokens.
  func chat(messages: [Chat.Message]) async throws -> String {
    try await chat(messages: messages, maxTokens: 1024)
  }

  /// Convenience matching `EuroLLMTranslator.chat`'s defaulted
  /// `maxTokens` — protocol requirements can't carry default values.
  func chat(prompt: String) async throws -> String {
    try await chat(prompt: prompt, maxTokens: 1024)
  }
}
