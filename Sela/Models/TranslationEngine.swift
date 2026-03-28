import Foundation

enum TranslationEngine: String, CaseIterable {
    case apple
    case deepl

    var displayName: String {
        switch self {
        case .apple: "Apple Translation"
        case .deepl: "DeepL"
        }
    }
}
