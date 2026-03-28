import Foundation

struct DiagnoseIssue {
    let id: String
    let groupName: String
    let slideIndex: Int
    let severity: Severity
    let message: String

    enum Severity {
        case warning, info
    }
}
