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
    case foundationModel

    var displayName: String {
        switch self {
        case .apple: "Apple Translation"
        case .googleTranslate: "Google Translate"
        case .myMemory: "MyMemory"
        case .deepl: "DeepL"
        case .gemini: "Google Gemini"
        case .foundationModel: "Apple Intelligence"
        }
    }

    /// Whether the engine needs a user-supplied API key to function.
    var requiresAPIKey: Bool {
        switch self {
        case .deepl, .gemini: true
        case .apple, .googleTranslate, .myMemory, .foundationModel: false
        }
    }

    /// Models the user can pick from. Empty when the provider exposes no choice.
    var availableModels: [AIModel] {
        switch self {
        case .gemini: AIModel.gemini
        case .deepl: AIModel.deepl
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

    static var isAppleTranslationAvailable: Bool {
        if #available(macOS 15, *) {
            return true
        }
        return false
    }

    /// Whether the engine can currently be used, given the configured API keys
    /// and the host OS. Drives which engines appear in the picker.
    func isAvailable(hasDeepLKey: Bool, hasGeminiKey: Bool) -> Bool {
        switch self {
        case .apple: Self.isAppleTranslationAvailable
        case .googleTranslate, .myMemory: true
        case .deepl: hasDeepLKey
        case .gemini: hasGeminiKey
        case .foundationModel: Self.isFoundationModelAvailable
        }
    }

    /// The engines available right now, in declaration order.
    static func available(hasDeepLKey: Bool, hasGeminiKey: Bool) -> [TranslationEngine] {
        allCases.filter { $0.isAvailable(hasDeepLKey: hasDeepLKey, hasGeminiKey: hasGeminiKey) }
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
}
