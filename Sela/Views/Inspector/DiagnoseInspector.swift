import SwiftUI

struct DiagnoseInspector: View {
    let song: Song
    let issues: [DiagnoseIssue]
    var onSelectIssue: ((DiagnoseIssue) -> Void)?
    var onFixIssue: ((DiagnoseIssue) -> Void)?
    var onFixAll: (() -> Void)?

    var body: some View {
        List {
            Section("Translation") {
                ProgressView(value: song.translationProgress) {
                    Text("\(translatedCount) of \(totalCount) slides translated")
                        .font(.caption)
                }
            }

            if !issues.isEmpty {
                Section {
                    ForEach(issues, id: \.id) { issue in
                        IssueRowView(issue: issue, onFix: onFixIssue)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectIssue?(issue) }
                    }
                } header: {
                    HStack {
                        Text("Issues")
                        Spacer()
                        if hasFixableIssues {
                            Button("Fix All") { onFixAll?() }
                                .font(.caption)
                                .buttonStyle(.borderless)
                        }
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

    private var hasFixableIssues: Bool {
        issues.contains { $0.fix != nil }
    }
}

struct IssueRowView: View {
    let issue: DiagnoseIssue
    var onFix: ((DiagnoseIssue) -> Void)?

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

            if issue.fix != nil {
                Spacer()
                Button {
                    onFix?(issue)
                } label: {
                    Image(systemName: "wrench.fill")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Fix this issue")
            }
        }
    }
}

#Preview("With Issues") {
    let song = MockSongProvider.buildMyLife
    DiagnoseInspector(
        song: song,
        issues: DiagnosticsEngine.diagnose(song: song, rules: DiagnosticRules.all)
    )
    .frame(width: 260, height: 400)
}

#Preview("No Translation") {
    DiagnoseInspector(song: MockSongProvider.wayMaker, issues: [])
        .frame(width: 260, height: 400)
}
