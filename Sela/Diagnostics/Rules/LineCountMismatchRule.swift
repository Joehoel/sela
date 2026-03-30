import Foundation

struct LineCountMismatchRule: DiagnosticRule {
    let id = "lineCountMismatch"
    let name = "Line count mismatch"
    let description = "Warns when the translation has a different number of lines than the original."
    let severity = DiagnoseIssue.Severity.warning
    let enabled = true

    func check(line: SlideLine, groupName: String, slideIndex: Int) -> DiagnoseIssue? {
        let originalLines = line.original.components(separatedBy: "\n").count
        let translationLines = line.translation.components(separatedBy: "\n").count
        guard originalLines != translationLines else { return nil }
        return DiagnoseIssue(
            id: line.id,
            lineID: line.id,
            groupName: groupName,
            slideIndex: slideIndex,
            severity: severity,
            message: "Line count mismatch: \(translationLines) vs \(originalLines) original"
        )
    }
}
