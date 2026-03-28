import Foundation
@testable import Sela
import Testing

struct GlossaryReplacementStepTests {
    // MARK: - Word replacement

    @Test("replaces informal pronoun with reverent form")
    func replaceInformalPronoun() async throws {
        let step = GlossaryReplacementStep(entries: [
            GlossaryEntry(source: "You", target: "U", replacements: ["Jij", "Je"]),
        ])
        var items = [TranslationItem(sourceText: "You give life", lineID: "1")]
        items[0].currentText = "Jij geeft leven"

        try await step.process(&items)
        #expect(items[0].currentText == "U geeft leven")
    }

    @Test("replacement is case-insensitive")
    func caseInsensitive() async throws {
        let step = GlossaryReplacementStep(entries: [
            GlossaryEntry(source: "You", target: "U", replacements: ["Jij"]),
        ])
        var items = [TranslationItem(sourceText: "you", lineID: "1")]
        items[0].currentText = "jij geeft leven"

        try await step.process(&items)
        #expect(items[0].currentText == "U geeft leven")
    }

    @Test("respects word boundaries")
    func wordBoundaries() async throws {
        let step = GlossaryReplacementStep(entries: [
            GlossaryEntry(source: "You", target: "U", replacements: ["Jij"]),
        ])
        var items = [TranslationItem(sourceText: "nearby", lineID: "1")]
        // "Bijina" contains "Jij" but should NOT be affected
        items[0].currentText = "Bijina klaar"

        try await step.process(&items)
        #expect(items[0].currentText == "Bijina klaar")
    }

    @Test("handles multiple replacements in one entry")
    func multipleReplacements() async throws {
        let step = GlossaryReplacementStep(entries: [
            GlossaryEntry(source: "You", target: "U", replacements: ["Jij", "Je"]),
        ])
        var items = [TranslationItem(sourceText: "You, You", lineID: "1")]
        items[0].currentText = "Jij en je"

        try await step.process(&items)
        #expect(items[0].currentText == "U en U")
    }

    @Test("applies multiple glossary entries")
    func multipleEntries() async throws {
        let step = GlossaryReplacementStep(entries: [
            GlossaryEntry(source: "You", target: "U", replacements: ["Jij"]),
            GlossaryEntry(source: "Your", target: "Uw", replacements: ["Jouw"]),
        ])
        var items = [TranslationItem(sourceText: "You and Your love", lineID: "1")]
        items[0].currentText = "Jij en jouw liefde"

        try await step.process(&items)
        #expect(items[0].currentText == "U en Uw liefde")
    }

    @Test("entries with empty replacements are skipped")
    func emptyReplacementsNoOp() async throws {
        let step = GlossaryReplacementStep(entries: [
            GlossaryEntry(source: "grace", target: "genade"),
        ])
        var items = [TranslationItem(sourceText: "grace", lineID: "1")]
        items[0].currentText = "gratie"

        try await step.process(&items)
        #expect(items[0].currentText == "gratie")
    }

    @Test("no entries means no changes")
    func noEntries() async throws {
        let step = GlossaryReplacementStep(entries: [])
        var items = [TranslationItem(sourceText: "Hello", lineID: "1")]
        items[0].currentText = "Hallo"

        try await step.process(&items)
        #expect(items[0].currentText == "Hallo")
    }

    // MARK: - String extension

    @Test("replacingWordOccurrences replaces whole words only")
    func stringExtension() {
        #expect("Jij bent groot".replacingWordOccurrences(of: "Jij", with: "U") == "U bent groot")
        #expect("Bijina klaar".replacingWordOccurrences(of: "Jij", with: "U") == "Bijina klaar")
        #expect("jij en jij".replacingWordOccurrences(of: "Jij", with: "U") == "U en U")
    }

    // MARK: - GlossaryEntry encoding

    @Test("GlossaryEntry round-trips through JSON")
    func encodingRoundTrip() throws {
        let entry = GlossaryEntry(source: "You", target: "U", replacements: ["Jij", "Je"])
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(GlossaryEntry.self, from: data)
        #expect(decoded.source == "You")
        #expect(decoded.target == "U")
        #expect(decoded.replacements == ["Jij", "Je"])
    }
}
