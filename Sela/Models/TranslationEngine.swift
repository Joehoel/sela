import Foundation

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

    static var isFoundationModelAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return true
            }
        #endif
        return false
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
}
