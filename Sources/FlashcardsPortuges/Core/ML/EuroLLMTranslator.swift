import Foundation

struct LLMTranslation: Codable, Equatable {
  struct Variants: Codable, Equatable {
    let direct: String
    let colloquial: String
    let relatedExamples: [RelatedExample]?
  }
  struct RelatedExample: Codable, Equatable, Identifiable {
    let english: String
    let portuguese: String
    var id: String { english + "::" + portuguese }
  }
  let translation: Variants
  let original: String
}

enum LLMDirection {
  case englishToPortuguese
  case portugueseToEnglish
}

struct LLMDefinition: Codable, Equatable {
  struct Example: Codable, Equatable, Identifiable {
    let portuguese: String
    let english: String
    var id: String { portuguese + "::" + english }
  }
  let term: String
  let partOfSpeech: String
  let definition: String
  let examples: [Example]
}

/// App-level facade over `MLXModelCoordinator` that runs EuroLLM with
/// the structured-JSON prompts the model is known to behave well on.
@MainActor
final class EuroLLMTranslator: ObservableObject, LLMTranslating {
  static let shared = EuroLLMTranslator()

  private let harness = MLXMemoryHarness()
  private lazy var coordinator = MLXModelCoordinator(harness: harness)

  enum Status: Equatable {
    case notLoaded
    case loading(fraction: Double)
    case ready
    case processing
    case failed(message: String)
  }

  @Published private(set) var status: Status = .notLoaded
  @Published private(set) var statusMessage: String = "Not loaded"

  /// Which `ModelCatalog` variant is currently resident in the
  /// coordinator. nil iff status is `.notLoaded` or `.failed`.
  @Published private(set) var activeVariant: ModelVariant?

  /// Which variant is currently being loaded (downloading + loading
  /// into MLX). nil unless `status == .loading`. Settings UI uses
  /// this to keep a row in "downloading" state instead of flipping
  /// to Load/Delete the moment HuggingFace creates the snapshot dir.
  @Published private(set) var pendingVariant: ModelVariant?

  var isReady: Bool {
    if case .ready = status { return true }
    if case .processing = status { return true }
    return false
  }

  var loadProgress: Double {
    if case .loading(let f) = status { return f }
    return 0
  }

  private var configured = false

  /// Current user preference for default variant, read from
  /// UserDefaults. `"auto"` means "best fit for hardware", anything
  /// else is a `ModelVariant.id`. SettingsView writes this via
  /// `@AppStorage`.
  private var activeVariantPreference: String {
    UserDefaults.standard.string(forKey: ModelCatalog.activeVariantDefaultsKey) ?? "auto"
  }
  
  /// Configure the harness with this machine's physical RAM. Safe
  /// to call multiple times — idempotent.
  func bootstrap() async {
    guard !configured else { return }
    let ram = Int(ProcessInfo.processInfo.physicalMemory)
    await harness.configure(physicalRAMBytes: ram)
    configured = true
    Logger.log("EuroLLM harness configured: physRAM=\(ram) bytes")
  }
  
  /// Auto-load on app startup if (a) the user's active-variant
  /// preference resolves to something already on disk, and (b) we can
  /// fit it without forcing a harness-rejection. Silent on failure:
  /// the user can still trigger a load explicitly from Settings.
  func autoLoadIfCached() {
    Task {
      let physRAM = Int(ProcessInfo.processInfo.physicalMemory)
      guard let variant = ModelCatalog.resolveActive(
        preference: activeVariantPreference,
        physicalRAMBytes: physRAM
      ) else {
        Logger.log("EuroLLM auto-load skipped: no on-disk variant matches preference '\(activeVariantPreference)'")
        return
      }
      Logger.log("EuroLLM auto-load resolved to \(variant.id); loading…")
      do {
        try await load(variant: variant)
      } catch {
        Logger.log("EuroLLM auto-load failed: \(error.localizedDescription)")
      }
    }
  }

  /// Lazy-load gate used by translate/chat/define/etc. If `isReady`,
  /// no-op. Otherwise resolve the active-variant preference (must be
  /// on disk) and load. Never auto-swaps a running variant — that's
  /// the explicit Load button's job.
  func ensureLoaded() async throws {
    if isReady { return }
    let physRAM = Int(ProcessInfo.processInfo.physicalMemory)
    guard let variant = ModelCatalog.resolveActive(
      preference: activeVariantPreference,
      physicalRAMBytes: physRAM
    ) else {
      throw MLXTranslatorError.noModelLoaded
    }
    try await load(variant: variant)
  }

  /// Load `variant` into the coordinator. If another variant is
  /// already loaded, unload it first (Settings "Load" semantics).
  /// Honors the harness pre-load admission check — throws
  /// `MLXTranslatorError.harnessRejection` if RAM is insufficient.
  /// Use `forceLoad` to bypass that check (after a user confirms via
  /// the warning sheet).
  func load(variant: ModelVariant) async throws {
    try await loadInternal(variant: variant, force: false)
  }

  /// Same as `load`, but skips the harness admission check. Used by
  /// the "Continue anyway" path on the insufficient-RAM warning
  /// sheet. The actual MLX load may still fail at OS level if the
  /// machine truly can't fit the weights; that surfaces as a
  /// `modelLoadFailed` error.
  func forceLoad(variant: ModelVariant) async throws {
    try await loadInternal(variant: variant, force: true)
  }

  private func loadInternal(variant: ModelVariant, force: Bool) async throws {
    await bootstrap()

    if await coordinator.isLoaded() {
      // Unload whatever's resident before swapping. If it's already
      // this variant, skip the round-trip.
      if activeVariant?.id == variant.id {
        status = .ready
        statusMessage = "Ready (\(variant.displayName))"
        return
      }
      await coordinator.unload()
      activeVariant = nil
    }

    if !force {
      let admission = await harness.canAccept(
        estimatedAdditionalBytes: variant.estimatedBytes
      )
      if case .rejected(let reason) = admission {
        status = .notLoaded
        statusMessage = "Not loaded"
        throw MLXTranslatorError.harnessRejection(reason: reason)
      }
    }

    pendingVariant = variant
    status = .loading(fraction: 0)
    statusMessage = "Loading \(variant.displayName)…"
    let progressPoller = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        if let fraction = await self.coordinator.loadProgressFraction {
          await MainActor.run {
            if case .loading = self.status {
              self.status = .loading(fraction: fraction)
              self.statusMessage = "Downloading \(variant.parameterScale.rawValue)… \(Int(fraction * 100))%"
            }
          }
        }
        try? await Task.sleep(for: .milliseconds(250))
      }
    }
    defer {
      progressPoller.cancel()
      pendingVariant = nil
    }

    do {
      try await coordinator.load(
        modelID: variant.id,
        huggingFaceRepo: variant.huggingFaceRepo,
        estimatedBytes: variant.estimatedBytes
      )
      activeVariant = variant
      status = .ready
      statusMessage = "Ready (\(variant.displayName))"
      Logger.log("EuroLLM loaded: \(variant.id)")
    } catch {
      activeVariant = nil
      status = .failed(message: error.localizedDescription)
      statusMessage = "Load failed: \(error.localizedDescription)"
      Logger.log("EuroLLM load failed for \(variant.id): \(error.localizedDescription)")
      throw error
    }
  }

  /// Unload the active variant from memory. Does NOT remove cached
  /// files. Safe to call when nothing is loaded.
  func unload() async {
    await coordinator.unload()
    let previous = activeVariant?.displayName
    activeVariant = nil
    status = .notLoaded
    statusMessage = "Unloaded"
    Logger.log("EuroLLM unloaded\(previous.map { " (\($0))" } ?? "")")
  }

  /// Remove `variant`'s cached weights from disk. If it's the active
  /// variant, unload it first.
  func delete(variant: ModelVariant) async {
    if activeVariant?.id == variant.id {
      await unload()
    }
    try? FileManager.default.removeItem(at: variant.cacheDir)
    try? FileManager.default.removeItem(at: variant.cacheDir.appendingPathExtension("incomplete"))
    Logger.log("EuroLLM cached model deleted: \(variant.id)")
  }
  
  /// Ask the LLM to classify the Portuguese phrase/word into one
  /// of the app's `PartOfSpeech` categories. Returns `nil` if the
  /// model is unavailable or the response can't be mapped to a
  /// known case. Defensive — never throws.
  func classifyPartOfSpeech(portuguese text: String) async -> PartOfSpeech? {
    guard isReady else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    
    let labels = PartOfSpeech.allCases.map { $0.rawValue }.joined(separator: ", ")
    let prompt = """
        Classify the following European Portuguese text into exactly one of these categories:
        \(labels).
        Reply with ONLY the category name in JSON format: { "category": "<one of the labels>" }
        <portuguese>\(trimmed)</portuguese>
        """
    do {
      status = .processing
      statusMessage = "Classifying…"
      defer {
        status = .ready
        statusMessage = "Ready"
      }
      let raw = try await coordinator.infer(prompt: prompt, maxTokens: 64, temperature: 0.0)
      Logger.log("EuroLLM POS classify raw: \(raw)")
      return Self.parsePartOfSpeech(raw)
    } catch {
      Logger.log("EuroLLM POS classify failed: \(error.localizedDescription)")
      return nil
    }
  }
  
  static func parsePartOfSpeech(_ raw: String) -> PartOfSpeech? {
    // Try strict JSON first.
    if let body = extractJSONBody(from: raw),
       let data = body.data(using: .utf8),
       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let category = dict["category"] as? String {
      return PartOfSpeech(rawValue: category)
      ?? PartOfSpeech.allCases.first { $0.rawValue.caseInsensitiveCompare(category) == .orderedSame }
    }
    // Loose fallback — substring match on the raw output.
    let lower = raw.lowercased()
    for pos in PartOfSpeech.allCases {
      if lower.contains(pos.rawValue.lowercased()) {
        return pos
      }
    }
    return nil
  }
  
  /// Single-field translate: detect the source language ("English"
  /// or "Portuguese") and translate to the other. Returns the same
  /// `LLMTranslation` shape the dual-direction call uses, plus the
  /// detected direction.
  func autoTranslate(_ text: String) async throws -> (translation: LLMTranslation, direction: LLMDirection) {
    try await ensureLoaded()
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let prompt = """
        Detect whether the following text is in English or European Portuguese, then translate it to the other language.
        Reply in JSON ONLY. The format is:
        {
          "sourceLanguage": "English" | "Portuguese",
          "translation": {
            "direct": "<literal translation in the target language>",
            "colloquial": "<idiomatic translation in the target language>",
            "relatedExamples": [
              { "english": "<example in English>", "portuguese": "<example in European Portuguese>" }
            ]
          },
          "original": "<the original input>"
        }
        Provide 2–3 related examples that illustrate the term in natural use.
        <text>\(trimmed)</text>
        """
    Logger.log("EuroLLM auto-translate prompt: \(prompt)")
    status = .processing
    statusMessage = "Translating…"
    defer {
      status = .ready
      statusMessage = "Ready"
    }
    let raw = try await coordinator.infer(prompt: prompt, maxTokens: 768, temperature: 0.2)
    Logger.log("EuroLLM auto-translate raw: \(raw)")
    
    let body = Self.extractJSONBody(from: raw) ?? raw
    guard let data = body.data(using: .utf8) else {
      throw MLXTranslatorError.responseParseFailed(raw: raw)
    }
    // Decode as a permissive intermediate so the existing
    // LLMTranslation type stays single-purpose.
    struct AutoEnvelope: Codable {
      let sourceLanguage: String
      let translation: LLMTranslation.Variants
      let original: String
    }
    do {
      let env = try JSONDecoder().decode(AutoEnvelope.self, from: data)
      let direction: LLMDirection = env.sourceLanguage.lowercased().hasPrefix("en")
      ? .englishToPortuguese
      : .portugueseToEnglish
      let translation = LLMTranslation(translation: env.translation, original: env.original)
      return (translation, direction)
    } catch {
      throw MLXTranslatorError.responseParseFailed(raw: raw)
    }
  }
  
  /// Resolve a possibly-English verb input to its Portuguese
  /// infinitive. Examples that should resolve:
  ///   "to go"  -> "ir"
  ///   "to eat" -> "comer"
  ///   "speak"  -> "falar"
  /// Returns `nil` if the input isn't a verb, or if the model isn't
  /// confident enough to commit to a single infinitive. Defensive:
  /// never throws — callers gate on `nil`.
  func portugueseInfinitive(forEnglish input: String) async -> String? {
    guard isReady else { return nil }
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let prompt = """
        You translate a single English verb to its European Portuguese infinitive.
        Reply in JSON ONLY. No prose. Format:
        { "isVerb": true|false, "infinitive": "<portuguese infinitive ending in -ar, -er, or -ir>" }
        If the input is not a verb, set isVerb to false and leave infinitive as "".
        Examples:
          input "to go"  -> { "isVerb": true, "infinitive": "ir" }
          input "speak"  -> { "isVerb": true, "infinitive": "falar" }
          input "house"  -> { "isVerb": false, "infinitive": "" }
        <english>\(trimmed)</english>
        """
    do {
      status = .processing
      statusMessage = "Resolving infinitive…"
      defer {
        status = .ready
        statusMessage = "Ready"
      }
      let raw = try await coordinator.infer(prompt: prompt, maxTokens: 64, temperature: 0.0)
      Logger.log("EuroLLM infinitive raw: \(raw)")
      guard let body = Self.extractJSONBody(from: raw),
            let data = body.data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
      }
      guard (dict["isVerb"] as? Bool) == true,
            let inf = (dict["infinitive"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            !inf.isEmpty else {
        return nil
      }
      // Sanity check the result is a plausible Portuguese
      // infinitive — the model occasionally returns conjugated
      // forms or English. Strict ending filter rejects garbage.
      guard inf.hasSuffix("ar") || inf.hasSuffix("er") || inf.hasSuffix("ir") else {
        return nil
      }
      return inf
    } catch {
      Logger.log("EuroLLM infinitive lookup failed: \(error.localizedDescription)")
      return nil
    }
  }
  
  /// Definition + a couple of example sentences for a Portuguese
  /// term. Keeps the JSON tight so parsing stays reliable on a 9B
  /// model: `definition` (≤2 sentences, plain English), `partOfSpeech`
  /// in Portuguese (matching `PartOfSpeech` raw values), and 2–3
  /// examples each pairing a Portuguese sentence with its English.
  func defineWithExamples(portuguese term: String) async throws -> LLMDefinition {
    try await ensureLoaded()
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    let prompt = """
        You are a European Portuguese-English dictionary assistant. Define the term inside the <term> tag.
        Reply in JSON ONLY. No surrounding prose. The format is:
        {
          "term": "<the term>",
          "partOfSpeech": "<one of: Verbo, Substantivo, Adjetivo, Advérbio, Preposição, Conjunção, Pronome, Frase>",
          "definition": "<a clear English definition, 1–2 sentences>",
          "examples": [
            { "portuguese": "<example sentence in European Portuguese>", "english": "<English translation>" },
            { "portuguese": "<another example sentence>", "english": "<English translation>" }
          ]
        }
        Provide 2–3 examples that show the term in natural use. Keep definitions concise.
        <term>\(trimmed)</term>
        """
    Logger.log("EuroLLM define prompt: \(prompt)")
    status = .processing
    statusMessage = "Defining…"
    defer {
      status = .ready
      statusMessage = "Ready"
    }
    let raw = try await coordinator.infer(prompt: prompt, maxTokens: 512, temperature: 0.2)
    Logger.log("EuroLLM define raw: \(raw)")
    let body = Self.extractJSONBody(from: raw) ?? raw
    guard let data = body.data(using: .utf8) else {
      throw MLXTranslatorError.responseParseFailed(raw: raw)
    }
    do {
      return try JSONDecoder().decode(LLMDefinition.self, from: data)
    } catch {
      throw MLXTranslatorError.responseParseFailed(raw: raw)
    }
  }
  
  /// Free-form chat against the loaded model. Sends the full prompt
  /// (system + conversation history) and returns the raw response.
  /// The caller builds the prompt via `ChatService.buildPrompt`.
  func chat(prompt: String, maxTokens: Int = 1024) async throws -> String {
    try await ensureLoaded()
    status = .processing
    statusMessage = "Thinking…"
    defer {
      status = .ready
      statusMessage = "Ready"
    }
    Logger.log("EuroLLM chat prompt length: \(prompt.count)")
    let raw = try await coordinator.infer(
      prompt: prompt,
      maxTokens: maxTokens,
      temperature: 0.7
    )
    Logger.log("EuroLLM chat response length: \(raw.count)")
    return raw
  }

  /// Translate `text` in the given direction. Returns the parsed
  /// JSON body — `direct` (literal) and `colloquial` (idiomatic).
  func translate(_ text: String, direction: LLMDirection) async throws -> LLMTranslation {
    try await ensureLoaded()
    let prompt = Self.buildPrompt(text: text, direction: direction)
    Logger.log("EuroLLM prompt: \(prompt)")
    status = .processing
    statusMessage = "Translating…"
    defer {
      status = .ready
      statusMessage = "Ready"
    }
    let raw = try await coordinator.infer(prompt: prompt, maxTokens: 512, temperature: 0.2)
    Logger.log("EuroLLM raw response: \(raw)")
    return try Self.parseJSON(raw, fallbackOriginal: text)
  }
  
  static func buildPrompt(text: String, direction: LLMDirection) -> String {
    switch direction {
    case .englishToPortuguese:
      return """
            Translate the following contents in the english tag to European Portuguese. Reply in JSON with a few related or example sentences.
            with the format of { "translation": { "direct": "", "colloquial": "", "relatedExamples": [ { "english": "", "portuguese": "" } ] }, "original":
            "<contents of source string>" }
            <english>\(text)</english>
            """
    case .portugueseToEnglish:
      return """
            Translate the following contents in the portuguese tag to American English. Reply in JSON with a few related or example sentences.
            with the format of { "translation": { "direct": "", "colloquial": "", "relatedExamples": [ { "english": "", "portuguese": "" } ] }, "original":
            "<contents of source string>" }
            <portuguese>\(text)</portuguese>
            """
    }
  }
  
  /// Tolerate leading/trailing prose around the JSON body, plus
  /// optional ```json fenced blocks. Picks the first balanced
  /// `{...}` substring and decodes it.
  static func parseJSON(_ raw: String, fallbackOriginal: String) throws -> LLMTranslation {
    let body = extractJSONBody(from: raw) ?? raw
    guard let data = body.data(using: .utf8) else {
      throw MLXTranslatorError.responseParseFailed(raw: raw)
    }
    do {
      return try JSONDecoder().decode(LLMTranslation.self, from: data)
    } catch {
      throw MLXTranslatorError.responseParseFailed(raw: raw)
    }
  }
  
  /// Pure string brace-matcher — `nonisolated` so non-MainActor
  /// callers (e.g. `ChatService.extractAction`) can reuse it.
  nonisolated static func extractJSONBody(from raw: String) -> String? {
    guard let firstBrace = raw.firstIndex(of: "{") else { return nil }
    var depth = 0
    var idx = firstBrace
    while idx < raw.endIndex {
      let ch = raw[idx]
      if ch == "{" { depth += 1 }
      if ch == "}" {
        depth -= 1
        if depth == 0 {
          return String(raw[firstBrace...idx])
        }
      }
      idx = raw.index(after: idx)
    }
    return nil
  }
}
