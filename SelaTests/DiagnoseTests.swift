import Testing
@testable import Sela

@Suite("Diagnose Issues")
struct DiagnoseTests {

    @Test("no issues for untranslated slides")
    func untranslatedHasNoIssues() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "Hello world")])
            ])
        ])
        #expect(song.diagnoseIssues.isEmpty)
    }

    @Test("no issues when translation matches original punctuation")
    func matchingPunctuation() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "I worship You", translation: "Ik aanbid U")])
            ])
        ])
        #expect(song.diagnoseIssues.isEmpty)
    }

    @Test("detects missing trailing punctuation")
    func missingPunctuation() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "I worship You.", translation: "Ik aanbid U")])
            ])
        ])
        let issues = song.diagnoseIssues
        #expect(issues.count == 1)
        #expect(issues[0].severity == .info)
        #expect(issues[0].message.contains("Missing trailing punctuation"))
    }

    @Test("detects extra trailing punctuation")
    func extraPunctuation() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "I worship You", translation: "Ik aanbid U.")])
            ])
        ])
        let issues = song.diagnoseIssues
        #expect(issues.count == 1)
        #expect(issues[0].severity == .info)
        #expect(issues[0].message.contains("Extra trailing punctuation"))
    }

    @Test("detects line count mismatch")
    func lineCountMismatch() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "Line one", translation: "Regel een\nRegel twee")])
            ])
        ])
        let issues = song.diagnoseIssues
        #expect(issues.contains { $0.severity == .warning })
        #expect(issues.contains { $0.message.contains("Line count mismatch") })
    }

    @Test("multiple issues on same song")
    func multipleIssues() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "Hello.", translation: "Hallo")]),
                Slide(lines: [SlideLine(original: "World", translation: "Wereld!")]),
            ])
        ])
        let issues = song.diagnoseIssues
        #expect(issues.count == 2)
    }

    @Test("issues include correct group name and slide index")
    func issueMetadata() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Chorus", slides: [
                Slide(lines: [SlideLine(original: "Praise!", translation: "Lofprijs")]),
            ])
        ])
        let issues = song.diagnoseIssues
        #expect(issues.count == 1)
        #expect(issues[0].groupName == "Chorus")
        #expect(issues[0].slideIndex == 0)
    }

    @Test("no issues when both have matching punctuation marks")
    func bothHavePunctuation() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "My God!", translation: "Mijn God!")])
            ])
        ])
        #expect(song.diagnoseIssues.isEmpty)
    }
}
