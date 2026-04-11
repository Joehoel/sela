import Foundation
import SwiftProtobuf

enum ProPresenterReader {
    /// Decodes a `.pro` file from disk and returns both the domain model and
    /// the underlying proto. Used by tests and the writer round-trip path.
    static func read(from url: URL) throws -> (Song, RVData_Presentation) {
        let data = try Data(contentsOf: url)
        let presentation = try RVData_Presentation(serializedBytes: data)
        let parsed = parseToDTO(presentation: presentation, url: url)
        return (Song(parsed: parsed), presentation)
    }

    /// Pure, nonisolated entry point used by the library-load hot path. Decodes
    /// with `discardUnknownFields` for speed; the save path re-reads the file
    /// fresh with default options so round-trip safety (unknown-field
    /// preservation) is maintained.
    static func parseToDTO(data: Data, url: URL) throws -> ParsedSong {
        var options = BinaryDecodingOptions()
        options.discardUnknownFields = true
        let presentation = try RVData_Presentation(serializedBytes: data, options: options)
        return parseToDTO(presentation: presentation, url: url)
    }

    static func parseToDTO(presentation: RVData_Presentation, url: URL) -> ParsedSong {
        let cuesByID = Dictionary(
            presentation.cues.map { ($0.uuid.string, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let slideGroups = presentation.cueGroups.map { group -> ParsedSlideGroup in
            let slides = group.cueIdentifiers.compactMap { cueID -> ParsedSlide? in
                guard let cue = cuesByID[cueID.string] else { return nil }
                return parsedSlideFromCue(cue)
            }
            return ParsedSlideGroup(
                id: group.group.uuid.string,
                name: group.group.name,
                slides: slides
            )
        }

        let title = presentation.ccli.songTitle.isEmpty
            ? presentation.name
            : presentation.ccli.songTitle

        return ParsedSong(
            id: presentation.uuid.string,
            title: title,
            author: presentation.ccli.author,
            slideGroups: slideGroups,
            filePath: url
        )
    }

    private static func parsedSlideFromCue(_ cue: RVData_Cue) -> ParsedSlide? {
        var lines: [ParsedLine] = []
        var hasTranslatableElement = false
        for action in cue.actions {
            let elements = action.slide.presentation.baseSlide.elements
            let textElements = elements.filter { $0.element.hasText && !$0.element.text.rtfData.isEmpty }
            guard let first = textElements.first else { continue }

            let original = RTFTextStripper.extractText(from: Data(first.element.text.rtfData))
            guard !original.isEmpty else { continue }

            let second = textElements.count >= 2 ? textElements[1] : nil
            let translation = second.map { RTFTextStripper.extractText(from: Data($0.element.text.rtfData)) } ?? ""

            if second != nil { hasTranslatableElement = true }

            lines.append(ParsedLine(
                id: first.element.uuid.string,
                original: original,
                translation: translation
            ))
        }
        guard !lines.isEmpty, hasTranslatableElement else { return nil }
        return ParsedSlide(id: cue.uuid.string, lines: lines)
    }
}
