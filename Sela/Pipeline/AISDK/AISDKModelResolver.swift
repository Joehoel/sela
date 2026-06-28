import AISDKProvider
import AnthropicProvider
import Foundation
import GoogleProvider
import OpenAIProvider

/// Errors raised while resolving a `LanguageModelV3` for an engine selection.
enum AISDKModelError: LocalizedError {
    case missingAPIKey(engine: TranslationEngine)
    case unsupportedEngine(TranslationEngine)

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(engine):
            "\(engine.displayName) API key is not configured. Set it in Settings."
        case let .unsupportedEngine(engine):
            "\(engine.displayName) is not supported by the unified translation step."
        }
    }
}

/// Resolves a `LanguageModelV3` for an LLM engine selection, constructing a
/// provider per call with the user-entered API key (no env vars). Key validation
/// is lazy — an invalid key surfaces on the first request, not here.
enum AISDKModelResolver {
    // swiftlint:disable:next cyclomatic_complexity
    static func model(
        for engine: TranslationEngine,
        apiKey: String,
        modelID: String
    ) throws -> any LanguageModelV3 {
        switch engine {
        case .gemini:
            guard !apiKey.isEmpty else { throw AISDKModelError.missingAPIKey(engine: engine) }
            let provider = createGoogleGenerativeAI(settings: .init(apiKey: apiKey))
            return try provider.languageModel(modelId: modelID)
        case .openAI:
            guard !apiKey.isEmpty else { throw AISDKModelError.missingAPIKey(engine: engine) }
            let provider = createOpenAIProvider(settings: .init(apiKey: apiKey))
            return try provider.languageModel(modelId: modelID)
        case .anthropic:
            guard !apiKey.isEmpty else { throw AISDKModelError.missingAPIKey(engine: engine) }
            let provider = createAnthropicProvider(settings: .init(apiKey: apiKey))
            return try provider.languageModel(modelId: modelID)
        case .deepl:
            // DeepL is a custom (non-LLM) model. `modelID` carries the DeepL
            // `model_type` (quality/latency). The key is validated lazily on the
            // first request, matching the LLM providers.
            guard !apiKey.isEmpty else { throw DeepLError.missingAPIKey }
            return DeepLLanguageModel(apiKey: apiKey, modelType: modelID.isEmpty ? nil : modelID)
        case .googleTranslate:
            // Free, key-free web endpoint. No key validation; lazy on first request.
            return GoogleTranslateLanguageModel()
        case .myMemory:
            // Free, key-free REST API. No key validation; lazy on first request.
            return MyMemoryLanguageModel()
        case .foundationModel:
            // Apple Intelligence (on-device FoundationModels). Key-free; gated to
            // Apple-Intelligence-capable hosts. Unsupported elsewhere so callers
            // fall back to the deferred-error path like a missing key.
            guard TranslationEngine.isFoundationModelAvailable else {
                throw AISDKModelError.unsupportedEngine(engine)
            }
            return FoundationModelLanguageModel()
        case .apple:
            // Apple Translation (headless on-device). Key-free; the headless
            // `TranslationSession(installedSource:target:)` needs macOS 26.
            // Unsupported elsewhere so callers fall back to the deferred-error path
            // like a missing key.
            if #available(macOS 26, *) {
                return AppleTranslationLanguageModel()
            }
            throw AISDKModelError.unsupportedEngine(engine)
        }
    }
}
