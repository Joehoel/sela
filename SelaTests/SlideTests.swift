import Testing
@testable import Sela

@Suite("Slide")
struct SlideTests {

    @Test("hasTranslation is false when translation is empty")
    func noTranslation() {
        let slide = Slide(lines: [SlideLine(original: "Hello")])
        #expect(!slide.hasTranslation)
    }

    @Test("hasTranslation is true when any line has translation")
    func withTranslation() {
        let slide = Slide(lines: [
            SlideLine(original: "Hello", translation: "Hallo"),
            SlideLine(original: "World"),
        ])
        #expect(slide.hasTranslation)
    }

    @Test("hasTranslation is false when translation is whitespace-only")
    func whitespaceOnly() {
        let slide = Slide(lines: [SlideLine(original: "Hello", translation: "")])
        #expect(!slide.hasTranslation)
    }
}
