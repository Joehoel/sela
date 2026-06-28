import Foundation

/// A selectable model offered by an AI provider that supports model selection.
/// `id` is the value sent to the provider's API; `displayName` is for the UI.
struct AIModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
}

enum TranslationEngine: String, CaseIterable {
    case apple
    case googleTranslate
    case myMemory
    case deepl
    case gemini
    case openAI
    case anthropic
    case foundationModel

    var displayName: String {
        switch self {
        case .apple: "Apple Translation"
        case .googleTranslate: "Google Translate"
        case .myMemory: "MyMemory"
        case .deepl: "DeepL"
        case .gemini: "Google Gemini"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .foundationModel: "Apple Intelligence"
        }
    }

    /// Whether the engine needs a user-supplied API key to function.
    var requiresAPIKey: Bool {
        switch self {
        case .deepl, .gemini, .openAI, .anthropic: true
        case .apple, .googleTranslate, .myMemory, .foundationModel: false
        }
    }

    /// Models the user can pick from. Empty when the provider exposes no choice.
    var availableModels: [AIModel] {
        switch self {
        case .gemini: AIModel.gemini
        case .deepl: AIModel.deepl
        case .openAI: AIModel.openAI
        case .anthropic: AIModel.anthropic
        case .apple, .googleTranslate, .myMemory, .foundationModel: []
        }
    }

    /// The default model, or `nil` when the engine has no model selection.
    var defaultModel: AIModel? {
        availableModels.first
    }

    static var isFoundationModelAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return true
            }
        #endif
        return false
    }

    /// Apple Translation is headless-only (macOS 26+): the session is built
    /// directly with `TranslationSession(installedSource:target:)`. Whether the
    /// engine is actually *offered* also requires the EN→NL pair to be installed —
    /// see the `appleTranslationInstalled` gate on `isAvailable`.
    static var isAppleTranslationAvailable: Bool {
        if #available(macOS 26, *) {
            return true
        }
        return false
    }

    /// Whether the engine can currently be used, given the configured API keys
    /// and the host OS. Drives which engines appear in the picker.
    ///
    /// `appleTranslationInstalled` is the async-resolved result of
    /// `AppleTranslationLanguageModel.installedLanguagePairAvailable()`. Apple
    /// Translation is only offered when macOS 26+ *and* the EN→NL pair is installed,
    /// because the headless session can't present the download-consent prompt.
    func isAvailable(
        hasDeepLKey: Bool,
        hasGeminiKey: Bool,
        hasOpenAIKey: Bool = false,
        hasAnthropicKey: Bool = false,
        appleTranslationInstalled: Bool = false
    ) -> Bool {
        switch self {
        case .apple: Self.isAppleTranslationAvailable && appleTranslationInstalled
        case .googleTranslate, .myMemory: true
        case .deepl: hasDeepLKey
        case .gemini: hasGeminiKey
        case .openAI: hasOpenAIKey
        case .anthropic: hasAnthropicKey
        case .foundationModel: Self.isFoundationModelAvailable
        }
    }

    /// The engines available right now, in declaration order.
    static func available(
        hasDeepLKey: Bool,
        hasGeminiKey: Bool,
        hasOpenAIKey: Bool = false,
        hasAnthropicKey: Bool = false,
        appleTranslationInstalled: Bool = false
    ) -> [TranslationEngine] {
        allCases.filter {
            $0.isAvailable(
                hasDeepLKey: hasDeepLKey,
                hasGeminiKey: hasGeminiKey,
                hasOpenAIKey: hasOpenAIKey,
                hasAnthropicKey: hasAnthropicKey,
                appleTranslationInstalled: appleTranslationInstalled
            )
        }
    }
}

enum RefinementEngine: String, CaseIterable {
    case foundationModel
    case gemini

    var displayName: String {
        switch self {
        case .foundationModel: "Apple Intelligence"
        case .gemini: "Google Gemini"
        }
    }

    var availableModels: [AIModel] {
        switch self {
        case .gemini: AIModel.gemini
        case .foundationModel: []
        }
    }

    var defaultModel: AIModel? {
        availableModels.first
    }

    func isAvailable(hasGeminiKey: Bool) -> Bool {
        switch self {
        case .gemini: hasGeminiKey
        case .foundationModel: TranslationEngine.isFoundationModelAvailable
        }
    }

    static func available(hasGeminiKey: Bool) -> [RefinementEngine] {
        allCases.filter { $0.isAvailable(hasGeminiKey: hasGeminiKey) }
    }
}

// MARK: - Model catalogs

extension AIModel {
    /// Gemini models for the `generateContent` endpoint. First entry is the
    /// default. `id` values are the API model names.
    static let gemini: [AIModel] = [
        AIModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
        AIModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro"),
        AIModel(id: "gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash-Lite"),
        AIModel(id: "gemini-3.5-flash", displayName: "Gemini 3.5 Flash"),
        AIModel(id: "gemini-3.1-pro-preview", displayName: "Gemini 3.1 Pro"),
        AIModel(id: "gemini-3.1-flash-lite", displayName: "Gemini 3.1 Flash-Lite"),
    ]

    /// DeepL `model_type` options. First entry is the default.
    static let deepl: [AIModel] = [
        AIModel(id: "latency_optimized", displayName: "Latency optimized"),
        AIModel(id: "quality_optimized", displayName: "Quality optimized (next-gen)"),
    ]

    /// OpenAI models routed through the SDK's Responses API. First entry is the
    /// default. Ids are open strings — any current OpenAI id passes through.
    static let openAI: [AIModel] = [
        AIModel(id: "gpt-5-mini", displayName: "GPT-5 mini"),
        AIModel(id: "gpt-5", displayName: "GPT-5"),
    ]

    /// Anthropic models routed through the SDK's Messages API. First entry is the
    /// default. Ids are open strings — any current Anthropic id passes through.
    static let anthropic: [AIModel] = [
        AIModel(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6"),
        AIModel(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5"),
    ]
}
