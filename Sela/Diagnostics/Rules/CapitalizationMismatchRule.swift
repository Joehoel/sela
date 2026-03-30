import Foundation

struct CapitalizationMismatchRule: DiagnosticRule {
    let id = "capitalizationMismatch"
    let name = "Capitalization mismatch"
    let description = "Notes when the translation starts with a different case than the original."
    let severity = DiagnoseIssue.Severity.info
    let enabled = true

    func check(line: SlideLine, groupName: String, slideIndex: Int) -> DiagnoseIssue? {
        guard let origFirst = line.original.first,
              let transFirst = line.translation.first else { return nil }
        guard origFirst.isUppercase != transFirst.isUppercase else { return nil }
        return DiagnoseIssue(
            id: "\(line.id)-cap",
            lineID: line.id,
            groupName: groupName,
            slideIndex: slideIndex,
            severity: severity,
            message: origFirst.isUppercase
                ? "Translation should start with uppercase"
                : "Translation starts with unexpected uppercase"
        )
    }

    func fix(line: SlideLine) -> String? {
        guard let origFirst = line.original.first,
              let transFirst = line.translation.first,
              origFirst.isUppercase != transFirst.isUppercase
        else { return nil }

        let rest = line.translation.dropFirst()
        if origFirst.isUppercase {
            return transFirst.uppercased() + rest
        } else {
            return transFirst.lowercased() + rest
        }
    }
}
