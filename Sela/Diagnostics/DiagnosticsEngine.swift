import Foundation

enum DiagnosticsEngine {
    static func diagnose(song: Song, rules: [any DiagnosticRule]) -> [DiagnoseIssue] {
        var result: [DiagnoseIssue] = []
        for group in song.slideGroups {
            for (slideIndex, slide) in group.slides.enumerated() {
                for line in slide.lines {
                    guard !line.translation.isEmpty else { continue }
                    for rule in rules {
                        if let issue = rule.check(line: line, groupName: group.name, slideIndex: slideIndex) {
                            result.append(issue)
                        }
                    }
                }
            }
        }
        return result
    }
}
