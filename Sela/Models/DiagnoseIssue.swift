import Foundation

struct DiagnoseIssue {
    let id: String
    let lineID: String
    let groupName: String
    let slideIndex: Int
    let severity: Severity
    let message: String
    var fix: (@MainActor (SlideLine) -> String)?

    enum Severity {
        case warning, info
    }
}
