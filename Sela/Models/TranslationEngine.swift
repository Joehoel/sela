import Foundation

enum TranslationEngine: String, CaseIterable {
    case apple
    case googleTranslate
    case myMemory
    case deepl
    case foundationModel

    var displayName: String {
        switch self {
        case .apple: "Apple Translation"
        case .googleTranslate: "Google Translate"
        case .myMemory: "MyMemory"
        case .deepl: "DeepL"
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
