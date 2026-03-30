import Foundation

enum TranslationEngine: String, CaseIterable {
    case apple
    case deepl
    case foundationModel

    var displayName: String {
        switch self {
        case .apple: "Apple Translation"
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
