import Foundation

struct LeadingTrailingWhitespaceRule: DiagnosticRule {
    let id = "leadingTrailingWhitespace"
    let name = "Leading/trailing whitespace"
    let description = "Flags leading or trailing whitespace in the translation."
    let severity = DiagnoseIssue.Severity.info
    let enabled = true

    func check(line: SlideLine, groupName: String, slideIndex: Int) -> DiagnoseIssue? {
        let trimmed = line.translation.trimmingCharacters(in: .whitespaces)
        guard trimmed != line.translation else { return nil }
        return DiagnoseIssue(
            id: "\(line.id)-ws",
            lineID: line.id,
            groupName: groupName,
            slideIndex: slideIndex,
            severity: severity,
            message: "Translation has leading or trailing whitespace"
        )
    }
}
