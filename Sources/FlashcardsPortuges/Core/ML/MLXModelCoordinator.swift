import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

struct MLXLoadedModel: Sendable {
  let modelID: String
  let huggingFaceRepo: String
  let container: ModelContainer
}

/// Owns the in-process LLM ModelContainer. Single-model variant —
/// EuroLLM is the only model this app loads. Inference goes through
/// ChatSession; load is gated by MLXMemoryHarness.
actor MLXModelCoordinator {
  private let harness: MLXMemoryHarness
  private var loaded: MLXLoadedModel?
  private var loadTask: Task<Void, Error>?
  
  private(set) var isLoadInFlight: Bool = false
  private(set) var loadProgressFraction: Double?
  private(set) var isInferenceInFlight: Bool = false
  
  init(harness: MLXMemoryHarness) {
    self.harness = harness
  }
  
  var loadedModelID: String? { loaded?.modelID }
  func isLoaded() -> Bool { loaded != nil }
  
  /// Load `huggingFaceRepo` (e.g. "stelterlab/EuroLLM-9B-Instruct-MLX-4bit").
  /// Returns when the container is resident and ready. Throws on
  /// harness rejection or fetch failure. Cancellable — call
  /// `cancelLoad()` to abort an in-flight download.
  ///
  /// `force` skips the harness admission check. The outer
  /// `EuroLLMTranslator.forceLoad` path already skips its own check;
  /// this parameter lets it skip the coordinator's mirror check too,
  /// so "Continue anyway" in the warning sheet actually proceeds
  /// instead of bouncing off this layer.
  func load(modelID: String, huggingFaceRepo: String, estimatedBytes: Int, force: Bool = false) async throws {
    if !force {
      let admission = await harness.canAccept(estimatedAdditionalBytes: estimatedBytes)
      if case .rejected(let reason) = admission {
        throw MLXTranslatorError.harnessRejection(reason: reason)
      }
    }
    
    isLoadInFlight = true
    defer { isLoadInFlight = false }
    
    let configuration = ModelConfiguration(id: huggingFaceRepo)
    
    let (stream, continuation) = AsyncStream<Double>.makeStream()
    let progressTask = Task { [weak self] in
      for await fraction in stream {
        await self?.updateLoadProgress(fraction)
      }
    }
    
    let container: ModelContainer
    do {
      container = try await #huggingFaceLoadModelContainer(
        configuration: configuration,
        progressHandler: { progress in
          continuation.yield(progress.fractionCompleted)
        }
      )
      continuation.finish()
      await progressTask.value
      loadProgressFraction = nil
    } catch {
      continuation.finish()
      await progressTask.value
      loadProgressFraction = nil
      await harness.didUnload()
      throw MLXTranslatorError.modelLoadFailed(
        modelID: modelID, reason: String(describing: error)
      )
    }
    
    if loaded != nil {
      await harness.didUnload()
    }
    loaded = MLXLoadedModel(
      modelID: modelID,
      huggingFaceRepo: huggingFaceRepo,
      container: container
    )
  }
  
  private func updateLoadProgress(_ fraction: Double) {
    loadProgressFraction = fraction
  }
  
  func unload() async {
    loaded = nil
    await harness.didUnload()
  }
  
  func cancelLoad() {
    loadTask?.cancel()
    loadTask = nil
  }
  
  /// Run a one-shot generation against the loaded container.
  func infer(prompt: String, maxTokens: Int = 512, temperature: Float = 0.2) async throws -> String {
    guard let model = loaded else {
      throw MLXTranslatorError.noModelLoaded
    }
    let admission = await harness.canAccept(estimatedAdditionalBytes: 0)
    if case .rejected(let reason) = admission {
      throw MLXTranslatorError.harnessRejection(reason: reason)
    }
    
    isInferenceInFlight = true
    defer { isInferenceInFlight = false }
    
    let session = ChatSession(
      model.container,
      generateParameters: GenerateParameters(
        maxTokens: maxTokens,
        temperature: temperature
      )
    )
    return try await session.respond(to: prompt)
  }
}

enum MLXTranslatorError: Error {
  case noModelLoaded
  case harnessRejection(reason: MLXLoadRejection)
  case modelLoadFailed(modelID: String, reason: String)
  case appleSiliconRequired
  case responseParseFailed(raw: String)
  case simulatorUnsupported

  var localizedDescription: String {
    switch self {
    case .noModelLoaded:
      return "EuroLLM is not loaded yet."
    case .harnessRejection(let reason):
      return reason.userMessage
    case .modelLoadFailed(let id, let reason):
      return "Loading '\(id)' failed: \(reason)"
    case .appleSiliconRequired:
      return "EuroLLM requires Apple Silicon."
    case .responseParseFailed(let raw):
      return "Could not parse model response as JSON. Raw: \(raw.prefix(200))"
    case .simulatorUnsupported:
      return "MLX inference is not supported in the iOS Simulator. The Metal backend's device init reads a property that is NULL on the simulator and crashes the process. Install on a real iPhone or iPad to download and run models."
    }
  }
}
