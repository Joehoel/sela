import Foundation

enum DiagnosticsEngine {
    static func diagnose(song: Song, rules: [any DiagnosticRule]) -> [DiagnoseIssue] {
        var result: [DiagnoseIssue] = []
        for group in song.slideGroups {
            for (slideIndex, slide) in group.slides.enumerated() {
                for line in slide.lines {
                    guard !line.translation.isEmpty else { continue }
                    for rule in rules {
                        guard var issue = rule.check(line: line, groupName: group.name, slideIndex: slideIndex) else {
                            continue
                        }
                        if rule.fix(line: line) != nil {
                            issue.fix = { line in rule.fix(line: line)! }
                        }
                        result.append(issue)
                    }
                }
            }
        }
        return result
    }
}
