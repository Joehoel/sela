@testable import Sela
import Testing

struct SongTests {
    @Test("hasTranslation is false when no translations")
    func noTranslation() {
        let song = Song(
            title: "Test",
            slideGroups: [
                SlideGroup(name: "Verse 1", slides: [
                    Slide(lines: [SlideLine(original: "Hello")])
                ]),
            ]
        )
        #expect(!song.hasTranslation)
    }

    @Test("hasTranslation is true when any slide has translation")
    func hasTranslation() {
        let song = Song(
            title: "Test",
            slideGroups: [
                SlideGroup(name: "Verse 1", slides: [
                    Slide(lines: [SlideLine(original: "Hello", translation: "Hallo")])
                ]),
            ]
        )
        #expect(song.hasTranslation)
    }

    @Test("slideCount returns total slides across groups")
    func slideCount() {
        let song = Song(
            title: "Test",
            slideGroups: [
                SlideGroup(name: "Verse 1", slides: [
                    Slide(lines: [SlideLine(original: "A")]),
                    Slide(lines: [SlideLine(original: "B")]),
                ]),
                SlideGroup(name: "Chorus", slides: [
                    Slide(lines: [SlideLine(original: "C")]),
                ]),
            ]
        )
        #expect(song.slideCount == 3)
    }

    @Test("translationProgress is correct for partial translation")
    func partialProgress() {
        let song = Song(
            title: "Test",
            slideGroups: [
                SlideGroup(name: "Verse 1", slides: [
                    Slide(lines: [SlideLine(original: "A", translation: "X")]),
                    Slide(lines: [SlideLine(original: "B")]),
                ]),
            ]
        )
        #expect(song.translatedSlideCount == 1)
        #expect(song.slideCount == 2)
        #expect(song.translationProgress == 0.5)
    }

    @Test("translationProgress is 1.0 when fully translated")
    func fullProgress() {
        let song = Song(
            title: "Test",
            slideGroups: [
                SlideGroup(name: "Verse 1", slides: [
                    Slide(lines: [SlideLine(original: "A", translation: "X")]),
                    Slide(lines: [SlideLine(original: "B", translation: "Y")]),
                ]),
            ]
        )
        #expect(song.translationProgress == 1.0)
    }

    @Test("translationProgress is 0 for empty song")
    func emptyProgress() {
        let song = Song(title: "Empty", slideGroups: [])
        #expect(song.translationProgress == 0)
        #expect(song.slideCount == 0)
        #expect(!song.hasTranslation)
    }
}
