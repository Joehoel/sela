import Foundation

protocol DiagnosticRule: Sendable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var severity: DiagnoseIssue.Severity { get }
    var enabled: Bool { get }
    func check(line: SlideLine, groupName: String, slideIndex: Int) -> DiagnoseIssue?
}

enum DiagnosticRules {
    static let all: [any DiagnosticRule] = [
        LineCountMismatchRule(),
        TrailingPunctuationRule(),
        CapitalizationMismatchRule(),
        LeadingTrailingWhitespaceRule(),
        SignificantLengthDifferenceRule(),
    ]

    static var defaultEnabledIDs: [String] {
        all.filter(\.enabled).map(\.id)
    }
}
