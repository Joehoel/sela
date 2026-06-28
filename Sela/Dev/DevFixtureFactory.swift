#if DEBUG
import AppKit
import Foundation

/// Makes more of the bundled fixtures usable in the dev library.
///
/// Several fixtures ship with a single text box per slide, so Sela has nothing
/// to translate in them. This appends an empty second text box (the translation
/// box) to every single-box slide, turning those songs into translatable ones.
///
/// DEBUG-only. The added box round-trips to zero characters, so saving a
/// translation into it also exercises the empty-box formatting fallback
/// (formatting is borrowed from the original box on save).
enum DevFixtureFactory {
    /// Appends a translation box to every slide that currently has exactly one
    /// text element. Returns how many boxes were added.
    @discardableResult
    static func addTranslationBoxes(to presentation: inout RVData_Presentation) -> Int {
        let emptyRTF = emptyRTFData()
        var added = 0

        for cueIndex in presentation.cues.indices {
            for actionIndex in presentation.cues[cueIndex].actions.indices {
                let elements = presentation.cues[cueIndex].actions[actionIndex]
                    .slide.presentation.baseSlide.elements
                let textIndices = elements.indices.filter {
                    elements[$0].element.hasText && !elements[$0].element.text.rtfData.isEmpty
                }
                guard textIndices.count == 1, let sourceIndex = textIndices.first else { continue }

                // Duplicate the original box, give it a fresh identity, and empty
                // its text so it reads as a blank translation box.
                var translationBox = elements[sourceIndex]
                translationBox.element.uuid.string = UUID().uuidString
                translationBox.element.text.rtfData = emptyRTF

                presentation.cues[cueIndex].actions[actionIndex]
                    .slide.presentation.baseSlide.elements.append(translationBox)
                added += 1
            }
        }

        return added
    }

    private static func emptyRTFData() -> Data {
        NSAttributedString(string: "")
            .rtf(from: NSRange(location: 0, length: 0), documentAttributes: [:]) ?? Data()
    }
}
#endif
