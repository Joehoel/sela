import Foundation
@testable import Sela
import Testing

/// Regressions found in the swift-ai-sdk migration code review.
struct AISDKRegressionFixTests {
    private func http200() -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    private func http(_ code: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: code, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - #2 Foundation Model maps by number, not position

    @Test("FoundationModel keys results by the echoed number, dropping invalid ones")
    func fmKeyByNumber() {
        let mapped = FoundationModelLanguageModel.keyByNumber(
            [(number: 2, text: "twee"), (number: 1, text: "een"), (number: 9, text: "drop")],
            valid: [1, 2, 3]
        )
        // Order preserved as returned; number 9 (not a source line) dropped.
        #expect(mapped == [TranslationLine(number: 2, text: "twee"), TranslationLine(number: 1, text: "een")])
    }

    // MARK: - #4 Refinement is best-effort

    @Test("refine steps are not required; translate steps are")
    func refineIsBestEffort() {
        let refine = TranslationPipeline.makeAISDKStep(
            engine: .gemini, apiKey: "k", modelID: "gemini-2.5-flash", mode: .refine
        )
        #expect(refine.isRequired == false)

        let translate = TranslationPipeline.makeAISDKStep(
            engine: .gemini, apiKey: "k", modelID: "gemini-2.5-flash", mode: .translate
        )
        #expect(translate.isRequired == true)

        // A resolution failure (missing key) in refine mode is also best-effort.
        let failingRefine = TranslationPipeline.makeAISDKStep(
            engine: .gemini, apiKey: "", modelID: "gemini-2.5-flash", mode: .refine
        )
        #expect(failingRefine.isRequired == false)
    }

    // MARK: - #5 Google Translate batches and falls back

    @Test("Google Translate sends one batched request and maps lines back")
    func googleBatchedMapping() async throws {
        let json = #"[[["Hallo\nWereld","Hello\nWorld",null,null,0]],null,"en"]"#
        let data = Data(json.utf8)
        let response = http200()
        let model = GoogleTranslateLanguageModel(transport: { _ in (data, response) })

        let lines = [
            CustomTranslationPrompt.SourceLine(number: 1, text: "Hello"),
            CustomTranslationPrompt.SourceLine(number: 2, text: "World"),
        ]
        let result = try await model.translate(lines)
        #expect(result == [TranslationLine(number: 1, text: "Hallo"), TranslationLine(number: 2, text: "Wereld")])
    }

    @Test("Google Translate falls back to source text when the split doesn't line up")
    func googleFallback() async throws {
        let json = #"[[["Hallo","Hello",null,null,0]],null,"en"]"#
        let data = Data(json.utf8)
        let model = GoogleTranslateLanguageModel(transport: { _ in (data, self.http200()) })

        let lines = [
            CustomTranslationPrompt.SourceLine(number: 1, text: "Hello"),
            CustomTranslationPrompt.SourceLine(number: 2, text: "World"),
        ]
        let result = try await model.translate(lines)
        // One translated part for two lines → keep source text rather than misalign.
        #expect(result == [TranslationLine(number: 1, text: "Hello"), TranslationLine(number: 2, text: "World")])
    }

    // MARK: - #3 Query encoding escapes & and +

    @Test("DeepL form body percent-encodes & and +")
    func deeplEncodesAmpersand() {
        let body = DeepLLanguageModel.formBody(for: ["Holy & Mighty + true"], modelType: nil)
        #expect(body.contains("%26")) // &
        #expect(body.contains("%2B")) // +
        #expect(!body.contains(" & "))
    }

    @Test("Google Translate request percent-encodes &")
    func googleEncodesAmpersand() throws {
        let request = try GoogleTranslateLanguageModel.buildRequest(for: "rock & roll")
        let url = try #require(request.url?.absoluteString)
        #expect(url.contains("%26"))
        #expect(!url.contains("rock & roll"))
    }
}
