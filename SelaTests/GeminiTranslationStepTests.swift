import Foundation
@testable import Sela
import Testing

struct GeminiTranslationStepTests {
    @Test("endpoint URL is built from the model id")
    func endpointURLFromModel() {
        let url = GeminiTranslationStep.endpointURL(for: "gemini-2.5-pro")
        #expect(url.absoluteString ==
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent")

        let preview = GeminiTranslationStep.endpointURL(for: "gemini-3.1-pro-preview")
        #expect(preview.absoluteString.contains("/models/gemini-3.1-pro-preview:generateContent"))
    }

    @Test("thinkingBudget is 0 only for the Flash tier")
    func thinkingBudgetPolicy() {
        #expect(GeminiTranslationStep.thinkingBudget(for: "gemini-2.5-flash") == 0)
        #expect(GeminiTranslationStep.thinkingBudget(for: "gemini-2.5-flash-lite") == 0)
        // Reasoning models reject budget 0 — must omit thinkingConfig.
        #expect(GeminiTranslationStep.thinkingBudget(for: "gemini-2.5-pro") == nil)
        #expect(GeminiTranslationStep.thinkingBudget(for: "gemini-3.1-pro-preview") == nil)
        #expect(GeminiTranslationStep.thinkingBudget(for: "gemini-3.5-flash") == nil)
    }

    @Test("request body omits thinkingConfig for reasoning models")
    func bodyOmitsThinkingConfigForReasoningModels() throws {
        let flash = GeminiTranslationStep.requestBody(systemPrompt: "s", userPrompt: "u", model: "gemini-2.5-flash")
        let flashGen = try #require(flash["generationConfig"] as? [String: Any])
        #expect(flashGen["thinkingConfig"] != nil)

        let pro = GeminiTranslationStep.requestBody(systemPrompt: "s", userPrompt: "u", model: "gemini-2.5-pro")
        let proGen = try #require(pro["generationConfig"] as? [String: Any])
        #expect(proGen["thinkingConfig"] == nil, "Pro rejects budget 0 — thinkingConfig must be omitted")
    }

    @Test("missing API key throws before making a request")
    func missingAPIKey() async {
        let step = GeminiTranslationStep(apiKey: "", model: "gemini-2.5-flash")
        var items = [TranslationItem(sourceText: "Hello", lineID: "1")]
        await #expect(throws: GeminiError.self) {
            try await step.process(&items)
        }
    }
}
