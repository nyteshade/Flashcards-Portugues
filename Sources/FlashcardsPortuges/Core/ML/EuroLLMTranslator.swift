import Foundation
import NaturalLanguage

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
  /// to call multiple times — idempotent. Throws on the iOS Simulator
  /// because MLX's Metal backend Device init reads a NULL property
  /// and crashes the process inside `std::string` (mlx/backend/metal/
  /// device.cpp:328). The first call into MLX from the simulator
  /// (`Memory.memoryLimit.setter` inside the harness) is what
  /// triggers it; bailing here surfaces a clean error before we touch
  /// MLX at all.
  func bootstrap() async throws {
    guard !configured else { return }
    #if targetEnvironment(simulator) && os(iOS)
    throw MLXTranslatorError.simulatorUnsupported
    #else
    let ram = Int(ProcessInfo.processInfo.physicalMemory)
    await harness.configure(physicalRAMBytes: ram)
    configured = true
    Logger.log("EuroLLM harness configured: physRAM=\(ram) bytes")
    #endif
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
    try await bootstrap()

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
        estimatedBytes: variant.estimatedBytes,
        force: force
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
  
  /// Single-field translate: detect the source language in Swift
  /// (NLLanguageRecognizer + Portuguese-diacritic check) and translate
  /// to the other. Returns the same `LLMTranslation` shape the
  /// directional call uses, plus the detected direction.
  ///
  /// Detecting in Swift instead of asking the model also avoids a
  /// failure mode the 1.7B variant hit on every call: it could not
  /// reliably produce the nested {sourceLanguage, translation:{…},
  /// original} envelope. Now the model only has to produce the
  /// translation envelope — same shape `translate(_:direction:)` is
  /// already validated against on 9B.
  func autoTranslate(_ text: String) async throws -> (translation: LLMTranslation, direction: LLMDirection) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let direction = Self.detectDirection(forInput: trimmed)
    let translation = try await translate(trimmed, direction: direction)
    return (translation, direction)
  }

  /// Heuristic source-language detection. Order:
  ///   1. Any Portuguese-distinctive diacritic → Portuguese.
  ///   2. NLLanguageRecognizer reports English with confidence ≥ 0.85
  ///      → English.
  ///   3. Default to Portuguese (the app is for learning Portuguese,
  ///      so PT-input is the more common ambiguous case).
  nonisolated static func detectDirection(forInput text: String) -> LLMDirection {
    let portugueseSignals: Set<Character> = [
      "ã", "õ", "â", "ê", "ô", "ç", "á", "í", "ó", "ú", "à"
    ]
    if text.lowercased().contains(where: { portugueseSignals.contains($0) }) {
      return .portugueseToEnglish
    }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
    if let englishConfidence = hypotheses[.english], englishConfidence >= 0.85 {
      return .englishToPortuguese
    }
    return .portugueseToEnglish
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
  /// If the JSON path produces empty strings (a known failure mode
  /// for small instruction-tuned models, which sometimes echo back
  /// the prompt's placeholder structure verbatim), retries with a
  /// plain-text prompt and uses that as `direct`.
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
    let parsed = try Self.parseJSON(raw, fallbackOriginal: text)
    if !parsed.translation.direct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
       !parsed.translation.colloquial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return parsed
    }
    // JSON parsed but both fields are blank — the model echoed our
    // template. Retry with a plain-text prompt and accept the line
    // as the direct translation.
    Logger.log("EuroLLM JSON returned empty values; retrying with plain-text prompt")
    let plainPrompt = Self.buildPlainTextPrompt(text: text, direction: direction)
    let plainRaw = try await coordinator.infer(prompt: plainPrompt, maxTokens: 256, temperature: 0.2)
    Logger.log("EuroLLM plain-text retry raw: \(plainRaw)")
    let cleaned = Self.cleanPlainTranslation(plainRaw)
    guard !cleaned.isEmpty else {
      throw MLXTranslatorError.responseParseFailed(raw: plainRaw)
    }
    return LLMTranslation(
      translation: LLMTranslation.Variants(
        direct: cleaned,
        colloquial: cleaned,
        relatedExamples: nil
      ),
      original: text
    )
  }

  static func buildPrompt(text: String, direction: LLMDirection) -> String {
    switch direction {
    case .englishToPortuguese:
      return """
            Translate the English text in the <english> tag to European Portuguese.
            Reply with valid JSON ONLY, no prose, no markdown, no code fences. Use this exact shape:
            { "translation": { "direct": "<literal translation, in European Portuguese>", "colloquial": "<natural idiomatic translation, in European Portuguese>" }, "original": "<the original English input>" }
            <english>\(text)</english>
            """
    case .portugueseToEnglish:
      return """
            Translate the European Portuguese text in the <portuguese> tag to American English.
            Reply with valid JSON ONLY, no prose, no markdown, no code fences. Use this exact shape:
            { "translation": { "direct": "<literal translation, in English>", "colloquial": "<natural idiomatic translation, in English>" }, "original": "<the original Portuguese input>" }
            <portuguese>\(text)</portuguese>
            """
    }
  }

  /// Plain-text fallback prompt used when the JSON path returns empty
  /// fields. Designed to maximize the chance a small model just emits
  /// the translated sentence and nothing else.
  static func buildPlainTextPrompt(text: String, direction: LLMDirection) -> String {
    switch direction {
    case .englishToPortuguese:
      return """
            Translate this English sentence to European Portuguese. Reply with the translated sentence only — no quotes, no labels, no explanation, no JSON.
            English: \(text)
            European Portuguese:
            """
    case .portugueseToEnglish:
      return """
            Translate this European Portuguese sentence to American English. Reply with the translated sentence only — no quotes, no labels, no explanation, no JSON.
            European Portuguese: \(text)
            English:
            """
    }
  }

  /// Strip the wrapping the model often adds around a single-line
  /// answer: leading labels ("English:", "Portuguese:"), surrounding
  /// quotes, markdown fences, and trailing prose after a blank line.
  nonisolated static func cleanPlainTranslation(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    // Take just the first non-empty line — the model sometimes
    // continues with explanation after the translation.
    if let firstLine = s.components(separatedBy: .newlines)
      .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
      s = firstLine
    }
    // Strip common label prefixes the model leaks past our prompt.
    let labelPrefixes = [
      "European Portuguese:", "Portuguese:", "American English:", "English:",
      "Translation:", "Tradução:",
    ]
    for prefix in labelPrefixes {
      if s.lowercased().hasPrefix(prefix.lowercased()) {
        s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
      }
    }
    // Strip surrounding quotes (straight and curly).
    let quotePairs: [(Character, Character)] = [
      ("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’"),
    ]
    for (open, close) in quotePairs {
      if s.first == open && s.last == close && s.count >= 2 {
        s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
      }
    }
    return s
  }
  
  /// Tolerate leading/trailing prose around the JSON body, plus
  /// optional ```json fenced blocks. Picks the first balanced
  /// `{...}` substring and decodes it. When strict decode fails
  /// (1.7B EuroLLM often emits malformed/partial JSON), falls back
  /// to a regex extractor that pulls out `direct` and `colloquial`
  /// from anywhere in the raw text. relatedExamples is dropped on
  /// the fallback path — small models almost never produce a clean
  /// array of objects, and the rest of the UI handles it being nil.
  static func parseJSON(_ raw: String, fallbackOriginal: String) throws -> LLMTranslation {
    let body = extractJSONBody(from: raw) ?? raw
    if let data = body.data(using: .utf8),
       let strict = try? JSONDecoder().decode(LLMTranslation.self, from: data) {
      return strict
    }
    let direct = firstCapturedString(in: raw, key: "direct")
    let colloquial = firstCapturedString(in: raw, key: "colloquial")
    let original = firstCapturedString(in: raw, key: "original") ?? fallbackOriginal
    guard direct != nil || colloquial != nil else {
      throw MLXTranslatorError.responseParseFailed(raw: raw)
    }
    let variants = LLMTranslation.Variants(
      direct: direct ?? colloquial ?? "",
      colloquial: colloquial ?? direct ?? "",
      relatedExamples: nil
    )
    return LLMTranslation(translation: variants, original: original)
  }

  /// Pull the first string value associated with `"key": "<value>"`
  /// anywhere in `haystack`. Tolerates whitespace, line breaks, and
  /// escaped quotes inside the value.
  nonisolated static func firstCapturedString(in haystack: String, key: String) -> String? {
    let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let range = NSRange(haystack.startIndex..., in: haystack)
    guard let match = regex.firstMatch(in: haystack, options: [], range: range),
          match.numberOfRanges > 1,
          let captured = Range(match.range(at: 1), in: haystack) else { return nil }
    // Unescape \" and \\ which JSON would normally handle.
    return String(haystack[captured])
      .replacingOccurrences(of: "\\\"", with: "\"")
      .replacingOccurrences(of: "\\\\", with: "\\")
      .replacingOccurrences(of: "\\n", with: "\n")
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
