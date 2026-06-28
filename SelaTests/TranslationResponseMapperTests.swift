import Foundation
@testable import Sela
import Testing

struct TranslationResponseMapperTests {
    private func items(_ sources: [String]) -> [TranslationItem] {
        sources.enumerated().map { TranslationItem(sourceText: $0.element, lineID: "\($0.offset)") }
    }

    @Test("assigns numbered lines to the matching items")
    func mapsInOrder() {
        var items = items(["one", "two", "three"])
        TranslationResponseMapper.apply("1. een\n2. twee\n3. drie", to: &items)
        #expect(items[0].currentText == "een")
        #expect(items[1].currentText == "twee")
        #expect(items[2].currentText == "drie")
    }

    /// The reported bug: Gemini returned the last two lines in swapped order.
    /// With per-line numbers, each translation must still land on its own line.
    @Test("maps correctly even when the model returns lines out of order")
    func mapsReorderedResponse() {
        var items = items([
            "Amazing grace, how sweet the sound",
            "That saved a wretch like me",
            "I once was lost, but now am found",
            "Was blind, but now I see",
        ])

        // Model returned lines 3 and 4 swapped.
        let response = """
        1. Genade groot, hoe zoet de klank
        2. Die mij, een zondaar, redde
        4. Verloren, maar gevonden
        3. Ik was eens blind, maar nu zie ik
        """

        TranslationResponseMapper.apply(response, to: &items)

        #expect(items[2].currentText == "Ik was eens blind, maar nu zie ik")
        #expect(items[3].currentText == "Verloren, maar gevonden")
    }

    @Test("ignores echoed group headers, blank lines, and preamble")
    func ignoresNonNumberedNoise() {
        var items = items(["one", "two"])
        let response = """
        Here are the translations:

        [Verse 1]
        1. een

        2. twee
        """
        TranslationResponseMapper.apply(response, to: &items)
        #expect(items[0].currentText == "een")
        #expect(items[1].currentText == "twee")
    }

    @Test("falls back to positional mapping when the model omits numbers")
    func legacyFallback() {
        var items = items(["one", "two"])
        TranslationResponseMapper.apply("een\ntwee", to: &items)
        #expect(items[0].currentText == "een")
        #expect(items[1].currentText == "twee")
    }

    @Test("buildUserPrompt numbers each line so results can be mapped back")
    func promptNumbersLines() {
        let items = items(["first line", "second line", "third line"])
        let prompt = TranslationPrompt(mode: .translate).buildUserPrompt(from: items)
        #expect(prompt.contains("1. EN: first line"))
        #expect(prompt.contains("2. EN: second line"))
        #expect(prompt.contains("3. EN: third line"))
    }

    @Test("refine prompt numbers both the source and the current translation")
    func refinePromptNumbersBothLines() {
        var item = TranslationItem(sourceText: "first line", lineID: "0")
        item.currentText = "eerste regel"
        let prompt = TranslationPrompt(mode: .refine).buildUserPrompt(from: [item])
        #expect(prompt.contains("1. EN: first line"))
        #expect(prompt.contains("1. NL: eerste regel"))
    }
}
