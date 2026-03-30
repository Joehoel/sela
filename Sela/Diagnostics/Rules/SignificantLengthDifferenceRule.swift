import Foundation

struct SignificantLengthDifferenceRule: DiagnosticRule {
    let id = "significantLengthDifference"
    let name = "Significant length difference"
    let description = "Flags when the translation is much longer or shorter than the original."
    let severity = DiagnoseIssue.Severity.info
    let enabled = false

    func check(line: SlideLine, groupName: String, slideIndex: Int) -> DiagnoseIssue? {
        let origLen = line.original.count
        let transLen = line.translation.count
        guard origLen > 0 else { return nil }
        let ratio = Double(transLen) / Double(origLen)
        guard ratio < 0.5 || ratio > 1.5 else { return nil }
        return DiagnoseIssue(
            id: "\(line.id)-len",
            lineID: line.id,
            groupName: groupName,
            slideIndex: slideIndex,
            severity: severity,
            message: transLen < origLen
                ? "Translation is much shorter than original"
                : "Translation is much longer than original"
        )
    }
}
