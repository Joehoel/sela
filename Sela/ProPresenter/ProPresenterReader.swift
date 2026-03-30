import Foundation

enum ProPresenterReader {
    static func read(from url: URL) throws -> (Song, RVData_Presentation) {
        let data = try Data(contentsOf: url)
        let presentation = try RVData_Presentation(serializedBytes: data)

        let cuesByID = Dictionary(
            presentation.cues.map { ($0.uuid.string, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let slideGroups = presentation.cueGroups.map { group -> SlideGroup in
            let slides = group.cueIdentifiers.compactMap { cueID -> Slide? in
                guard let cue = cuesByID[cueID.string] else { return nil }
                return slideFromCue(cue)
            }
            return SlideGroup(
                id: group.group.uuid.string,
                name: group.group.name,
                slides: slides
            )
        }

        let title = presentation.ccli.songTitle.isEmpty
            ? presentation.name
            : presentation.ccli.songTitle

        let song = Song(
            id: presentation.uuid.string,
            title: title,
            author: presentation.ccli.author,
            slideGroups: slideGroups,
            filePath: url
        )

        return (song, presentation)
    }

    private static func slideFromCue(_ cue: RVData_Cue) -> Slide? {
        var lines: [SlideLine] = []
        var hasTranslatableElement = false
        for action in cue.actions {
            let elements = action.slide.presentation.baseSlide.elements
            let textElements = elements.filter { $0.element.hasText && !$0.element.text.rtfData.isEmpty }
            guard let first = textElements.first else { continue }

            let original = RTFHelper.extractText(from: Data(first.element.text.rtfData))
            guard !original.isEmpty else { continue }

            let second = textElements.count >= 2 ? textElements[1] : nil
            let translation = second.map { RTFHelper.extractText(from: Data($0.element.text.rtfData)) } ?? ""

            if second != nil { hasTranslatableElement = true }

            lines.append(SlideLine(
                id: first.element.uuid.string,
                original: original,
                translation: translation
            ))
        }
        guard !lines.isEmpty, hasTranslatableElement else { return nil }
        return Slide(id: cue.uuid.string, lines: lines)
    }
}
