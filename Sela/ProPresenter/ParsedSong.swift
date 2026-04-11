import Foundation

/// Sendable snapshot of a parsed ProPresenter song.
///
/// The `@Observable` model types (`Song`, `SlideGroup`, `Slide`, `SlideLine`)
/// are reference types and not Sendable, so library-load work is done off
/// the main actor on these value-type DTOs, then converted to model types on
/// the main actor in a single cheap pass.
struct ParsedSong {
    let id: String
    let title: String
    let author: String
    let slideGroups: [ParsedSlideGroup]
    let filePath: URL
}

struct ParsedSlideGroup {
    let id: String
    let name: String
    let slides: [ParsedSlide]
}

struct ParsedSlide {
    let id: String
    let lines: [ParsedLine]
}

struct ParsedLine {
    let id: String
    let original: String
    let translation: String
}

// MARK: - DTO → model conversion

extension Song {
    convenience init(parsed: ParsedSong) {
        self.init(
            id: parsed.id,
            title: parsed.title,
            author: parsed.author,
            slideGroups: parsed.slideGroups.map { SlideGroup(parsed: $0) },
            filePath: parsed.filePath
        )
    }
}

extension SlideGroup {
    convenience init(parsed: ParsedSlideGroup) {
        self.init(
            id: parsed.id,
            name: parsed.name,
            slides: parsed.slides.map { Slide(parsed: $0) }
        )
    }
}

extension Slide {
    convenience init(parsed: ParsedSlide) {
        self.init(id: parsed.id, lines: parsed.lines.map { SlideLine(parsed: $0) })
    }
}

extension SlideLine {
    convenience init(parsed: ParsedLine) {
        self.init(id: parsed.id, original: parsed.original, translation: parsed.translation)
    }
}
