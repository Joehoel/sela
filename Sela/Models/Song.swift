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
