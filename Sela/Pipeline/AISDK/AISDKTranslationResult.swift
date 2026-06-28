import Foundation

/// One translated line, keyed by its 1-based source-line number. The number maps
/// the translation back to its source line so the model reordering lines can
/// never misassign a translation (see `AISDKTranslationStep.apply`).
struct TranslationLine: Codable, Sendable, Equatable {
    let number: Int
    let text: String
}

/// The structured object the LLM returns: one `TranslationLine` per input line.
/// Used as the `generateObject` schema so line mapping is structural rather than
/// parsed out of free text.
struct TranslationResult: Codable, Sendable {
    let translations: [TranslationLine]
}
