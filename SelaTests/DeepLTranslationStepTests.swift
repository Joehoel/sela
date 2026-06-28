import Foundation
@testable import Sela
import Testing

struct DeepLTranslationStepTests {
    // MARK: - Response parsing

    @Test("parses valid DeepL response")
    func parseValidResponse() throws {
        let json = """
        {"translations":[{"text":"Hallo wereld"},{"text":"Goedemorgen"}]}
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(DeepLResponse.self, from: data)
        #expect(response.translations.count == 2)
        #expect(response.translations[0].text == "Hallo wereld")
        #expect(response.translations[1].text == "Goedemorgen")
    }

    @Test("parses single translation response")
    func parseSingleTranslation() throws {
        let json = """
        {"translations":[{"text":"Test vertaling"}]}
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(DeepLResponse.self, from: data)
        #expect(response.translations.count == 1)
        #expect(response.translations[0].text == "Test vertaling")
    }

    // MARK: - Error types

    @Test("DeepLError has user-friendly descriptions")
    func errorDescriptions() {
        #expect(DeepLError.missingAPIKey.errorDescription?.contains("not configured") == true)
        #expect(DeepLError.authenticationFailed.errorDescription?.contains("invalid") == true)
        #expect(DeepLError.rateLimitExceeded.errorDescription?.contains("rate limit") == true)
        #expect(DeepLError.requestFailed(statusCode: 500).errorDescription?.contains("500") == true)
        #expect(DeepLError.invalidResponse.errorDescription?.contains("unexpected") == true)
    }

    @Test("missing API key throws before making request")
    func missingAPIKey() async {
        let step = DeepLTranslationStep(apiKey: "")
        var items = [TranslationItem(sourceText: "Hello", lineID: "1")]
        await #expect(throws: DeepLError.self) {
            try await step.process(&items)
        }
    }

    // MARK: - Request body / model_type

    @Test("form body omits model_type when none is selected")
    func formBodyWithoutModelType() {
        let body = DeepLTranslationStep.formBody(for: ["Hello"], modelType: nil)
        #expect(body.contains("text=Hello"))
        #expect(body.contains("source_lang=EN"))
        #expect(body.contains("target_lang=NL"))
        #expect(!body.contains("model_type"))
    }

    @Test("form body includes model_type when selected")
    func formBodyWithModelType() {
        let body = DeepLTranslationStep.formBody(for: ["Hello"], modelType: "quality_optimized")
        #expect(body.contains("model_type=quality_optimized"))
    }

    // MARK: - TranslationEngine

    @Test("TranslationEngine raw values")
    func engineRawValues() {
        #expect(TranslationEngine.apple.rawValue == "apple")
        #expect(TranslationEngine.deepl.rawValue == "deepl")
    }

    @Test("TranslationEngine display names")
    func engineDisplayNames() {
        #expect(TranslationEngine.apple.displayName == "Apple Translation")
        #expect(TranslationEngine.deepl.displayName == "DeepL")
    }

    @Test("TranslationEngine initializes from raw value")
    func engineFromRawValue() {
        #expect(TranslationEngine(rawValue: "apple") == .apple)
        #expect(TranslationEngine(rawValue: "deepl") == .deepl)
        #expect(TranslationEngine(rawValue: "invalid") == nil)
    }
}
