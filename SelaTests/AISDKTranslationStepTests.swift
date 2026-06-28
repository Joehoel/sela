import AISDKProvider
import Foundation
@testable import Sela
import Testing

/// A fake `LanguageModelV3` that returns a fixed JSON text payload, so the
/// `generateObject` structured-output path can be exercised end-to-end without
/// touching the network.
private struct FakeLanguageModel: LanguageModelV3 {
    let provider = "fake"
    let modelId = "fake-model"
    let json: String
    /// Captures the standardized prompt the SDK sends to `doGenerate`, so tests
    /// can assert request building.
    let onGenerate: (@Sendable (LanguageModelV3CallOptions) -> Void)?

    init(json: String, onGenerate: (@Sendable (LanguageModelV3CallOptions) -> Void)? = nil) {
        self.json = json
        self.onGenerate = onGenerate
    }

    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        onGenerate?(options)
        return LanguageModelV3GenerateResult(
            content: [.text(LanguageModelV3Text(text: json))],
            finishReason: LanguageModelV3FinishReason(unified: .stop),
            usage: LanguageModelV3Usage()
        )
    }

    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { $0.finish() }
        return LanguageModelV3StreamResult(stream: stream)
    }
}

struct AISDKTranslationStepTests {
    // MARK: - Structured mapping

    @Test("maps structured result back onto items by line number")
    func mapsByNumber() {
        var items = [
            TranslationItem(sourceText: "Hello", lineID: "a"),
            TranslationItem(sourceText: "World", lineID: "b"),
        ]
        let result = TranslationResult(translations: [
            TranslationLine(number: 1, text: "Hallo"),
            TranslationLine(number: 2, text: "Wereld"),
        ])
        AISDKTranslationStep.apply(result, to: &items)
        #expect(items[0].currentText == "Hallo")
        #expect(items[1].currentText == "Wereld")
    }

    @Test("reordered structured result still lands on the correct line")
    func reorderedMapping() {
        var items = [
            TranslationItem(sourceText: "Hello", lineID: "a"),
            TranslationItem(sourceText: "World", lineID: "b"),
            TranslationItem(sourceText: "Friend", lineID: "c"),
        ]
        let result = TranslationResult(translations: [
            TranslationLine(number: 3, text: "Vriend"),
            TranslationLine(number: 1, text: "Hallo"),
            TranslationLine(number: 2, text: "Wereld"),
        ])
        AISDKTranslationStep.apply(result, to: &items)
        #expect(items[0].currentText == "Hallo")
        #expect(items[1].currentText == "Wereld")
        #expect(items[2].currentText == "Vriend")
    }

    @Test("out-of-range numbers are ignored")
    func outOfRangeIgnored() {
        var items = [TranslationItem(sourceText: "Hello", lineID: "a")]
        let result = TranslationResult(translations: [
            TranslationLine(number: 0, text: "nope"),
            TranslationLine(number: 5, text: "nope"),
            TranslationLine(number: 1, text: "Hallo"),
        ])
        AISDKTranslationStep.apply(result, to: &items)
        #expect(items[0].currentText == "Hallo")
    }

    @Test("strips a leading number the model echoed into the text")
    func stripsEchoedNumber() {
        var items = [
            TranslationItem(sourceText: "Amazing grace", lineID: "a"),
            TranslationItem(sourceText: "How sweet the sound", lineID: "b"),
        ]
        // Model wrongly prefixed the translation with its line number.
        let result = TranslationResult(translations: [
            TranslationLine(number: 1, text: "1. Genade groot"),
            TranslationLine(number: 2, text: "2) Hoe zoet de klank"),
        ])
        AISDKTranslationStep.apply(result, to: &items)
        #expect(items[0].currentText == "Genade groot")
        #expect(items[1].currentText == "Hoe zoet de klank")
    }

    @Test("does not strip a leading number that is part of the translation")
    func keepsLegitimateLeadingNumber() {
        // number=1, but the text legitimately starts with a different number,
        // or the same number without a separator — must be left untouched.
        #expect(AISDKTranslationStep.strippingEchoedNumber("1 Korinthe 13", number: 1) == "1 Korinthe 13")
        #expect(AISDKTranslationStep.strippingEchoedNumber("3 keer heilig", number: 1) == "3 keer heilig")
        #expect(AISDKTranslationStep.strippingEchoedNumber("Genade groot", number: 1) == "Genade groot")
    }

    // MARK: - End-to-end through generateObject (no network)

    @Test("runs the SDK structured path and writes translations back")
    func endToEndStructured() async throws {
        let json = """
        {"translations":[{"number":1,"text":"Hallo"},{"number":2,"text":"Wereld"}]}
        """
        let model = FakeLanguageModel(json: json)
        let step = AISDKTranslationStep(model: model, mode: .translate)

        var items = [
            TranslationItem(sourceText: "Hello", lineID: "a"),
            TranslationItem(sourceText: "World", lineID: "b"),
        ]
        try await step.process(&items)
        #expect(items[0].currentText == "Hallo")
        #expect(items[1].currentText == "Wereld")
    }

    @Test("sends the numbered source lines in the prompt")
    func promptCarriesNumberedLines() async throws {
        let json = """
        {"translations":[{"number":1,"text":"Hallo"}]}
        """
        let captured = PromptCapture()
        let model = FakeLanguageModel(json: json) { options in
            captured.store(options.prompt)
        }
        let step = AISDKTranslationStep(model: model, mode: .translate)

        var items = [TranslationItem(sourceText: "Hello", lineID: "a")]
        try await step.process(&items)

        let text = captured.allText()
        #expect(text.contains("Hello"))
        #expect(text.contains("1."))
    }

    @Test("empty items short-circuit without calling the model")
    func emptyItems() async throws {
        let model = FakeLanguageModel(json: "{}")
        let step = AISDKTranslationStep(model: model, mode: .translate)
        var items: [TranslationItem] = []
        try await step.process(&items)
        #expect(items.isEmpty)
    }

    // MARK: - Omitted-line guard (translate mode)

    @Test("translate mode throws when the model omits a line")
    func translateThrowsOnOmittedLine() async {
        // Two source lines, model returns only line 1.
        let json = """
        {"translations":[{"number":1,"text":"Hallo"}]}
        """
        let step = AISDKTranslationStep(model: FakeLanguageModel(json: json), mode: .translate)
        var items = [
            TranslationItem(sourceText: "Hello", lineID: "a"),
            TranslationItem(sourceText: "World", lineID: "b"),
        ]
        await #expect(throws: AISDKTranslationError.self) {
            try await step.process(&items)
        }
    }

    @Test("refine mode keeps the prior translation when a line is omitted")
    func refineKeepsPriorOnOmittedLine() async throws {
        let json = """
        {"translations":[{"number":1,"text":"Hallo verfijnd"}]}
        """
        let step = AISDKTranslationStep(model: FakeLanguageModel(json: json), mode: .refine)
        var items = [
            TranslationItem(sourceText: "Hello", lineID: "a"),
            TranslationItem(sourceText: "World", lineID: "b"),
        ]
        items[0].currentText = "Hallo"
        items[1].currentText = "Wereld" // prior translation must survive
        try await step.process(&items)
        #expect(items[0].currentText == "Hallo verfijnd")
        #expect(items[1].currentText == "Wereld")
    }

    // MARK: - Error mapping

    @Test("classify maps auth and rate-limit errors, ignores others")
    func classifyErrors() {
        func err(_ message: String) -> NSError {
            NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
        }
        #expect(AISDKTranslationError.classify(err("HTTP 403 Forbidden")) == .authenticationFailed)
        #expect(AISDKTranslationError.classify(err("Invalid API key")) == .authenticationFailed)
        #expect(AISDKTranslationError.classify(err("429 rate limit exceeded")) == .rateLimitExceeded)
        #expect(AISDKTranslationError.classify(err("RESOURCE_EXHAUSTED")) == .rateLimitExceeded)
        #expect(AISDKTranslationError.classify(err("connection reset")) == nil)
    }

    // MARK: - Provider tuning

    @Test("temperature is 0.3 for LLM engines, nil for custom backends")
    func temperatureTuning() {
        #expect(AISDKTranslationStep.temperature(for: .gemini) == 0.3)
        #expect(AISDKTranslationStep.temperature(for: .openAI) == 0.3)
        #expect(AISDKTranslationStep.temperature(for: .anthropic) == 0.3)
        #expect(AISDKTranslationStep.temperature(for: .deepl) == nil)
        #expect(AISDKTranslationStep.temperature(for: .googleTranslate) == nil)
    }

    @Test("thinkingBudget provider option only for the Gemini Flash tier")
    func thinkingProviderOptions() {
        #expect(AISDKTranslationStep.providerOptions(for: .gemini, modelID: "gemini-2.5-flash")?["google"]?["thinkingConfig"] != nil)
        #expect(AISDKTranslationStep.providerOptions(for: .gemini, modelID: "gemini-2.5-flash-lite")?["google"] != nil)
        // Reasoning models reject budget 0 → no options.
        #expect(AISDKTranslationStep.providerOptions(for: .gemini, modelID: "gemini-2.5-pro") == nil)
        #expect(AISDKTranslationStep.providerOptions(for: .gemini, modelID: "gemini-3.1-pro-preview") == nil)
        #expect(AISDKTranslationStep.providerOptions(for: .openAI, modelID: "gpt-5") == nil)
    }

    // MARK: - Step naming

    @Test("step name reflects the mode")
    func stepName() {
        let model = FakeLanguageModel(json: "{}")
        #expect(AISDKTranslationStep(model: model, mode: .translate).name == "Translating…")
        #expect(AISDKTranslationStep(model: model, mode: .refine).name == "Refining…")
    }
}

/// Thread-safe capture box for the prompt passed to the fake model.
private final class PromptCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var prompt: LanguageModelV3Prompt = []

    func store(_ p: LanguageModelV3Prompt) {
        lock.lock(); defer { lock.unlock() }
        prompt = p
    }

    func allText() -> String {
        lock.lock(); defer { lock.unlock() }
        var pieces: [String] = []
        for message in prompt {
            switch message {
            case let .user(content, _):
                for part in content {
                    if case let .text(textPart) = part {
                        pieces.append(textPart.text)
                    }
                }
            case let .system(text, _):
                pieces.append(text)
            default:
                break
            }
        }
        return pieces.joined(separator: "\n")
    }
}
