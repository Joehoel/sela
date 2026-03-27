import SwiftUI

struct DiagnoseInspector: View {
    let song: Song

    var body: some View {
        List {
            Section("Translation") {
                ProgressView(value: song.translationProgress) {
                    Text("\(translatedCount) of \(totalCount) slides translated")
                        .font(.caption)
                }
            }

            if !issues.isEmpty {
                Section("Issues") {
                    ForEach(issues, id: \.id) { issue in
                        IssueRowView(issue: issue)
                    }
                }
            } else if song.hasTranslation {
                Section("Issues") {
                    Label("No issues found", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Diagnose")
    }

    private var totalCount: Int {
        song.slideGroups.flatMap(\.slides).count
    }

    private var translatedCount: Int {
        song.slideGroups.flatMap(\.slides).filter(\.hasTranslation).count
    }

    private var issues: [DiagnoseIssue] {
        var result: [DiagnoseIssue] = []
        for group in song.slideGroups {
            for (slideIndex, slide) in group.slides.enumerated() {
                for line in slide.lines {
                    guard !line.translation.isEmpty else { continue }

                    let originalLines = line.original.components(separatedBy: "\n").count
                    let translationLines = line.translation.components(separatedBy: "\n").count
                    if originalLines != translationLines {
                        result.append(DiagnoseIssue(
                            id: line.id,
                            groupName: group.name,
                            slideIndex: slideIndex,
                            severity: .warning,
                            message: "Line count mismatch: \(translationLines) vs \(originalLines) original"
                        ))
                    }

                    let originalEndsWithPunctuation = line.original.last.map { ".,!?;:".contains($0) } ?? false
                    let translationEndsWithPunctuation = line.translation.last.map { ".,!?;:".contains($0) } ?? false
                    if originalEndsWithPunctuation != translationEndsWithPunctuation {
                        result.append(DiagnoseIssue(
                            id: "\(line.id)-punct",
                            groupName: group.name,
                            slideIndex: slideIndex,
                            severity: .info,
                            message: originalEndsWithPunctuation
                                ? "Missing trailing punctuation"
                                : "Extra trailing punctuation"
                        ))
                    }
                }
            }
        }
        return result
    }
}

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

struct IssueRowView: View {
    let issue: DiagnoseIssue

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: issue.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(issue.severity == .warning ? .orange : .blue)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(issue.groupName), slide \(issue.slideIndex + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(issue.message)
                    .font(.caption)
            }
        }
    }
}
