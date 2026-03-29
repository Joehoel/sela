import Foundation
import Observation

@Observable
class Song: Identifiable {
    let id: String
    var title: String
    var author: String
    var category: String
    var slideGroups: [SlideGroup]
    var filePath: URL?
    var isHidden: Bool = false

    var hasTranslation: Bool {
        slideGroups.contains { group in
            group.slides.contains { slide in
                slide.lines.contains { !$0.translation.isEmpty }
            }
        }
    }

    var slideCount: Int {
        slideGroups.flatMap(\.slides).count
    }

    var translatedSlideCount: Int {
        slideGroups.flatMap(\.slides).filter(\.hasTranslation).count
    }

    var translationProgress: Double {
        guard slideCount > 0 else { return 0 }
        return Double(translatedSlideCount) / Double(slideCount)
    }

    var diagnoseIssues: [DiagnoseIssue] {
        var result: [DiagnoseIssue] = []
        for group in slideGroups {
            for (slideIndex, slide) in group.slides.enumerated() {
                for line in slide.lines {
                    guard !line.translation.isEmpty else { continue }

                    let originalLines = line.original.components(separatedBy: "\n").count
                    let translationLines = line.translation.components(separatedBy: "\n").count
                    if originalLines != translationLines {
                        result.append(DiagnoseIssue(
                            id: line.id,
                            lineID: line.id,
                            groupName: group.name,
                            slideIndex: slideIndex,
                            severity: .warning,
                            message: "Line count mismatch: \(translationLines) vs \(originalLines) original"
                        ))
                    }

                    let originalEnds = line.original.last.map { ".,!?;:".contains($0) } ?? false
                    let translationEnds = line.translation.last.map { ".,!?;:".contains($0) } ?? false
                    if originalEnds != translationEnds {
                        result.append(DiagnoseIssue(
                            id: "\(line.id)-punct",
                            lineID: line.id,
                            groupName: group.name,
                            slideIndex: slideIndex,
                            severity: .info,
                            message: originalEnds
                                ? "Missing trailing punctuation"
                                : "Extra trailing punctuation"
                        ))
                    }
                }
            }
        }
        return result
    }

    func clearTranslations() {
        for group in slideGroups {
            for slide in group.slides {
                for line in slide.lines {
                    line.translation = ""
                }
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        author: String = "",
        category: String = "",
        slideGroups: [SlideGroup] = [],
        filePath: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.category = category
        self.slideGroups = slideGroups
        self.filePath = filePath
    }
}
