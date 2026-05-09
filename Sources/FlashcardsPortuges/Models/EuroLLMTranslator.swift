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
final class EuroLLMTranslator: ObservableObject {
  static let shared = EuroLLMTranslator()
  
  /// HuggingFace repo path. Matches the LM Studio variant the user
  /// has been validating against.
  static let huggingFaceRepo = "stelterlab/EuroLLM-9B-Instruct-MLX-4bit"
  static let modelID = "eurollm-9b-instruct-mlx-4bit"
  
  /// Approximate resident weight footprint at 4-bit quantization.
  /// Used by the harness pre-load gate so a 16 GB Mac doesn't try
  /// to load this against, say, an already-loaded second model.
  /// Real on-disk size is ~5.4 GB; bumped slightly for runtime overhead.
  static let estimatedBytes = 6 * 1024 * 1024 * 1024
  
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
  
  /// Configure the harness with this machine's physical RAM. Safe
  /// to call multiple times — idempotent.
  func bootstrap() async {
    guard !configured else { return }
    let ram = Int(ProcessInfo.processInfo.physicalMemory)
    await harness.configure(physicalRAMBytes: ram)
    configured = true
    Logger.log("EuroLLM harness configured: physRAM=\(ram) bytes")
  }
  
  /// True iff the model weights appear to already be cached on disk
  /// at `~/.cache/huggingface/hub/models--<owner>--<repo>/`. The
  /// snapshot subdir presence is enough — first call after boot may
  /// still hit a partial cache if a previous download was cancelled,
  /// but `loadContainer` will recover by re-fetching missing files.
  static func isModelOnDisk() -> Bool {
    let owner = "stelterlab"
    let repo = "EuroLLM-9B-Instruct-MLX-4bit"
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dir = home
      .appendingPathComponent(".cache/huggingface/hub")
      .appendingPathComponent("models--\(owner)--\(repo)")
      .appendingPathComponent("snapshots")
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
          isDir.boolValue else { return false }
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    return !contents.isEmpty
  }
  
  /// Auto-load if the weights are already on disk. Called from app
  /// startup. Silent on failure — the user can still trigger a
  /// load from Settings if this no-ops or the cache turns out broken.
  func autoLoadIfCached() {
    Task {
      guard Self.isModelOnDisk() else {
        Logger.log("EuroLLM auto-load skipped: model not on disk")
        return
      }
      Logger.log("EuroLLM auto-load: model present on disk, loading…")
      do {
        try await ensureLoaded()
      } catch {
        Logger.log("EuroLLM auto-load failed: \(error.localizedDescription)")
      }
    }
  }
  
  /// Load EuroLLM into the coordinator. First call downloads (~5.4 GB);
  /// subsequent calls hit the swift-transformers disk cache.
  func ensureLoaded() async throws {
    await bootstrap()
    if await coordinator.isLoaded() {
      status = .ready
      statusMessage = "Ready"
      return
    }
    status = .loading(fraction: 0)
    statusMessage = "Loading EuroLLM-9B-Instruct (4-bit)…"
    let progressPoller = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        if let fraction = await self.coordinator.loadProgressFraction {
          await MainActor.run {
            if case .loading = self.status {
              self.status = .loading(fraction: fraction)
              self.statusMessage = "Downloading… \(Int(fraction * 100))%"
            }
          }
        }
        try? await Task.sleep(for: .milliseconds(250))
      }
    }
    defer { progressPoller.cancel() }
    
    do {
      try await coordinator.load(
        modelID: Self.modelID,
        huggingFaceRepo: Self.huggingFaceRepo,
        estimatedBytes: Self.estimatedBytes
      )
      status = .ready
      statusMessage = "Ready"
      Logger.log("EuroLLM loaded successfully")
    } catch {
      status = .failed(message: error.localizedDescription)
      statusMessage = "Load failed: \(error.localizedDescription)"
      Logger.log("EuroLLM load failed: \(error.localizedDescription)")
      throw error
    }
  }
  
  /// Unload the model from memory. Does NOT remove cached files.
  func unload() async {
    await coordinator.unload()
    status = .notLoaded
    statusMessage = "Unloaded"
    Logger.log("EuroLLM unloaded")
  }
  
  /// Remove the cached model files from disk. Unloads first if loaded.
  func deleteCachedModel() async {
    if await coordinator.isLoaded() {
      await coordinator.unload()
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dir = home
      .appendingPathComponent(".cache/huggingface/hub")
      .appendingPathComponent("models--stelterlab--EuroLLM-9B-Instruct-MLX-4bit")
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.removeItem(at: dir.appendingPathExtension("incomplete"))
    status = .notLoaded
    statusMessage = "Not loaded"
    Logger.log("EuroLLM cached model deleted")
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
  
  static func extractJSONBody(from raw: String) -> String? {
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
