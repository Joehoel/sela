import Foundation

/// Carries text through the translation pipeline, accumulating transformations.
struct TranslationItem {
    let sourceText: String
    var currentText: String
    let lineID: String
    let groupName: String?

    init(sourceText: String, lineID: String, groupName: String? = nil) {
        self.sourceText = sourceText
        self.currentText = sourceText
        self.lineID = lineID
        self.groupName = groupName
    }
}

/// What the user asked for — the editor resolves this to concrete lines.
enum TranslationRequest: Equatable {
    case emptySlides
    case allSlides
    case lines([String])
}
