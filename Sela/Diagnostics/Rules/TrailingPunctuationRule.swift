import Foundation

struct TrailingPunctuationRule: DiagnosticRule {
    let id = "trailingPunctuation"
    let name = "Trailing punctuation mismatch"
    let description = "Notes when original and translation differ in trailing punctuation."
    let severity = DiagnoseIssue.Severity.info
    let enabled = true

    func check(line: SlideLine, groupName: String, slideIndex: Int) -> DiagnoseIssue? {
        let punctuation = ".,!?;:"
        let originalEnds = line.original.last.map { punctuation.contains($0) } ?? false
        let translationEnds = line.translation.last.map { punctuation.contains($0) } ?? false
        guard originalEnds != translationEnds else { return nil }
        return DiagnoseIssue(
            id: "\(line.id)-punct",
            lineID: line.id,
            groupName: groupName,
            slideIndex: slideIndex,
            severity: severity,
            message: originalEnds ? "Missing trailing punctuation" : "Extra trailing punctuation"
        )
    }

    func fix(line: SlideLine) -> String? {
        let punctuation = ".,!?;:"
        let originalEnds = line.original.last.map { punctuation.contains($0) } ?? false
        let translationEnds = line.translation.last.map { punctuation.contains($0) } ?? false
        guard originalEnds != translationEnds else { return nil }

        if originalEnds, let punct = line.original.last {
            return line.translation + String(punct)
        } else {
            return String(line.translation.dropLast())
        }
    }
}
