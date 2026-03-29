import SwiftUI

struct DiagnoseInspector: View {
    let song: Song
    var onSelectIssue: ((DiagnoseIssue) -> Void)?

    var body: some View {
        List {
            Section("Translation") {
                ProgressView(value: song.translationProgress) {
                    Text("\(translatedCount) of \(totalCount) slides translated")
                        .font(.caption)
                }
            }

            if !song.diagnoseIssues.isEmpty {
                Section("Issues") {
                    ForEach(song.diagnoseIssues, id: \.id) { issue in
                        IssueRowView(issue: issue)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectIssue?(issue) }
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

#Preview("With Issues") {
    DiagnoseInspector(song: MockSongProvider.buildMyLife)
        .frame(width: 260, height: 400)
}

#Preview("No Translation") {
    DiagnoseInspector(song: MockSongProvider.wayMaker)
        .frame(width: 260, height: 400)
}
