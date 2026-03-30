@testable import Sela
import Testing

struct DiagnoseTests {
    // MARK: - Engine (existing behavior preserved)

    private let allRules = DiagnosticRules.all

    @Test("no issues for untranslated slides")
    func untranslatedHasNoIssues() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "Hello world")]),
            ]),
        ])
        #expect(DiagnosticsEngine.diagnose(song: song, rules: allRules).isEmpty)
    }

    @Test("no issues when translation matches original punctuation")
    func matchingPunctuation() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "I worship You", translation: "Ik aanbid U")]),
            ]),
        ])
        #expect(DiagnosticsEngine.diagnose(song: song, rules: allRules).isEmpty)
    }

    @Test("detects missing trailing punctuation")
    func missingPunctuation() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "I worship You.", translation: "Ik aanbid U")]),
            ]),
        ])
        let issues = DiagnosticsEngine.diagnose(song: song, rules: allRules)
        #expect(issues.contains { $0.severity == .info && $0.message.contains("Missing trailing punctuation") })
    }

    @Test("detects extra trailing punctuation")
    func extraPunctuation() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "I worship You", translation: "Ik aanbid U.")]),
            ]),
        ])
        let issues = DiagnosticsEngine.diagnose(song: song, rules: allRules)
        #expect(issues.contains { $0.severity == .info && $0.message.contains("Extra trailing punctuation") })
    }

    @Test("detects line count mismatch")
    func lineCountMismatch() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "Line one", translation: "Regel een\nRegel twee")]),
            ]),
        ])
        let issues = DiagnosticsEngine.diagnose(song: song, rules: allRules)
        #expect(issues.contains { $0.severity == .warning && $0.message.contains("Line count mismatch") })
    }

    @Test("multiple issues on same song")
    func multipleIssues() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "Hello.", translation: "Hallo")]),
                Slide(lines: [SlideLine(original: "World", translation: "Wereld!")]),
            ]),
        ])
        let issues = DiagnosticsEngine.diagnose(song: song, rules: allRules)
        #expect(issues.count(where: { $0.message.contains("punctuation") }) == 2)
    }

    @Test("issues include correct group name and slide index")
    func issueMetadata() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Chorus", slides: [
                Slide(lines: [SlideLine(original: "Praise!", translation: "Lofprijs")]),
            ]),
        ])
        let issues = DiagnosticsEngine.diagnose(song: song, rules: allRules)
        let punctIssue = issues.first { $0.message.contains("punctuation") }
        #expect(punctIssue?.groupName == "Chorus")
        #expect(punctIssue?.slideIndex == 0)
    }

    @Test("no issues when both have matching punctuation marks")
    func bothHavePunctuation() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "Verse 1", slides: [
                Slide(lines: [SlideLine(original: "My God!", translation: "Mijn God!")]),
            ]),
        ])
        #expect(DiagnosticsEngine.diagnose(song: song, rules: allRules).isEmpty)
    }

    // MARK: - Disabled rules are excluded

    @Test("disabled rules produce no issues")
    func disabledRulesExcluded() {
        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "V1", slides: [
                Slide(lines: [SlideLine(original: "Hello.", translation: "Hallo")]),
            ]),
        ])
        let issues = DiagnosticsEngine.diagnose(song: song, rules: [])
        #expect(issues.isEmpty)
    }

    // MARK: - Individual rule tests

    @Test("LineCountMismatchRule detects mismatch")
    func lineCountRule() {
        let line = SlideLine(original: "One line", translation: "Two\nlines")
        let issue = LineCountMismatchRule().check(line: line, groupName: "V1", slideIndex: 0)
        #expect(issue != nil)
        #expect(issue?.severity == .warning)
    }

    @Test("TrailingPunctuationRule detects missing punctuation")
    func punctuationRule() {
        let line = SlideLine(original: "Hello.", translation: "Hallo")
        let issue = TrailingPunctuationRule().check(line: line, groupName: "V1", slideIndex: 0)
        #expect(issue != nil)
        #expect(issue?.message == "Missing trailing punctuation")
    }

    @Test("CapitalizationMismatchRule detects case difference")
    func capitalizationRule() {
        let line = SlideLine(original: "Hello", translation: "hallo")
        let issue = CapitalizationMismatchRule().check(line: line, groupName: "V1", slideIndex: 0)
        #expect(issue != nil)
        #expect(issue?.message == "Translation should start with uppercase")
    }

    @Test("CapitalizationMismatchRule passes when case matches")
    func capitalizationRulePass() {
        let line = SlideLine(original: "Hello", translation: "Hallo")
        let issue = CapitalizationMismatchRule().check(line: line, groupName: "V1", slideIndex: 0)
        #expect(issue == nil)
    }

    @Test("LeadingTrailingWhitespaceRule detects whitespace")
    func whitespaceRule() {
        let line = SlideLine(original: "Hello", translation: " Hallo ")
        let issue = LeadingTrailingWhitespaceRule().check(line: line, groupName: "V1", slideIndex: 0)
        #expect(issue != nil)
    }

    @Test("LeadingTrailingWhitespaceRule passes when clean")
    func whitespaceRulePass() {
        let line = SlideLine(original: "Hello", translation: "Hallo")
        let issue = LeadingTrailingWhitespaceRule().check(line: line, groupName: "V1", slideIndex: 0)
        #expect(issue == nil)
    }

    @Test("SignificantLengthDifferenceRule detects much shorter translation")
    func lengthRuleShorter() {
        let line = SlideLine(original: "This is a long sentence", translation: "Kort")
        let issue = SignificantLengthDifferenceRule().check(line: line, groupName: "V1", slideIndex: 0)
        #expect(issue != nil)
        #expect(issue?.message == "Translation is much shorter than original")
    }

    @Test("SignificantLengthDifferenceRule detects much longer translation")
    func lengthRuleLonger() {
        let line = SlideLine(original: "Short", translation: "This is a much longer translation text")
        let issue = SignificantLengthDifferenceRule().check(line: line, groupName: "V1", slideIndex: 0)
        #expect(issue != nil)
        #expect(issue?.message == "Translation is much longer than original")
    }

    @Test("SignificantLengthDifferenceRule passes for similar lengths")
    func lengthRulePass() {
        let line = SlideLine(original: "Hello world", translation: "Hallo wereld")
        let issue = SignificantLengthDifferenceRule().check(line: line, groupName: "V1", slideIndex: 0)
        #expect(issue == nil)
    }

    @Test("SignificantLengthDifferenceRule is disabled by default")
    func lengthRuleDisabledByDefault() {
        #expect(!SignificantLengthDifferenceRule().enabled)
    }

    // MARK: - Fix methods

    @Test("TrailingPunctuationRule fix adds missing punctuation")
    func fixMissingPunctuation() {
        let line = SlideLine(original: "Hello.", translation: "Hallo")
        let fixed = TrailingPunctuationRule().fix(line: line)
        #expect(fixed == "Hallo.")
    }

    @Test("TrailingPunctuationRule fix removes extra punctuation")
    func fixExtraPunctuation() {
        let line = SlideLine(original: "Hello", translation: "Hallo.")
        let fixed = TrailingPunctuationRule().fix(line: line)
        #expect(fixed == "Hallo")
    }

    @Test("CapitalizationMismatchRule fix uppercases first character")
    func fixCapitalizationUpper() {
        let line = SlideLine(original: "Hello", translation: "hallo")
        let fixed = CapitalizationMismatchRule().fix(line: line)
        #expect(fixed == "Hallo")
    }

    @Test("CapitalizationMismatchRule fix lowercases first character")
    func fixCapitalizationLower() {
        let line = SlideLine(original: "hello", translation: "Hallo")
        let fixed = CapitalizationMismatchRule().fix(line: line)
        #expect(fixed == "hallo")
    }

    @Test("LeadingTrailingWhitespaceRule fix trims whitespace")
    func fixWhitespace() {
        let line = SlideLine(original: "Hello", translation: " Hallo ")
        let fixed = LeadingTrailingWhitespaceRule().fix(line: line)
        #expect(fixed == "Hallo")
    }

    @Test("LineCountMismatchRule has no fix")
    func lineCountNoFix() {
        let line = SlideLine(original: "One line", translation: "Two\nlines")
        let fixed = LineCountMismatchRule().fix(line: line)
        #expect(fixed == nil)
    }

    @Test("SignificantLengthDifferenceRule has no fix")
    func lengthNoFix() {
        let line = SlideLine(original: "This is a long sentence", translation: "Kort")
        let fixed = SignificantLengthDifferenceRule().fix(line: line)
        #expect(fixed == nil)
    }
}
