import Foundation

enum ProPresenterWriter {
    static func save(_ song: Song, into presentation: inout RVData_Presentation, at url: URL) throws {
        let slideIndex = buildSlideIndex(from: song)

        for cueIndex in presentation.cues.indices {
            let cueID = presentation.cues[cueIndex].uuid.string
            guard let slide = slideIndex[cueID],
                  let line = slide.lines.first,
                  !line.translation.isEmpty
            else { continue }

            updateTranslationElement(
                in: &presentation.cues[cueIndex],
                with: line.translation
            )
        }

        let data = try presentation.serializedData()

        // Create backup before overwriting
        let backupURL = url.appendingPathExtension("bak")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: url, to: backupURL)
        }

        try data.write(to: url, options: .atomic)
    }

    private static func buildSlideIndex(from song: Song) -> [String: Slide] {
        var index: [String: Slide] = [:]
        for group in song.slideGroups {
            for slide in group.slides {
                index[slide.id] = slide
            }
        }
        return index
    }

    private static func updateTranslationElement(
        in cue: inout RVData_Cue,
        with translation: String
    ) {
        for actionIndex in cue.actions.indices {
            let elements = cue.actions[actionIndex].slide.presentation.baseSlide.elements
            let textIndices = elements.indices.filter {
                elements[$0].element.hasText && !elements[$0].element.text.rtfData.isEmpty
            }
            guard textIndices.count >= 2 else { continue }

            let secondIndex = textIndices[1]
            let rtfData = Data(elements[secondIndex].element.text.rtfData)
            let newRTF = RTFHelper.replaceText(in: rtfData, with: translation)
            cue.actions[actionIndex]
                .slide.presentation.baseSlide
                .elements[secondIndex].element.text.rtfData = newRTF
        }
    }
}
