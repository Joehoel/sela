import Foundation

protocol DiagnosticRule: Sendable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var severity: DiagnoseIssue.Severity { get }
    var enabled: Bool { get }
    func check(line: SlideLine, groupName: String, slideIndex: Int) -> DiagnoseIssue?
    func fix(line: SlideLine) -> String?
}

extension DiagnosticRule {
    func fix(line _: SlideLine) -> String? {
        nil
    }
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
