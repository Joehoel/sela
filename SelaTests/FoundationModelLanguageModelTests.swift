import AISDKProvider
import Foundation
@testable import Sela
import SwiftAISDK
import Testing

/// Apple Intelligence (on-device FoundationModels) wrapped as a custom
/// `LanguageModelV3`. It is a real LLM, so unlike the REST backends it produces
/// the structured `[{number,text}]` result itself via guided generation — but it
/// still flows through the same unified `AISDKTranslationStep`, consuming the full
/// standardized prompt (so refine mode, which carries the `NL:` lines, works too).
///
/// The on-device call is injected so these tests run without Apple Intelligence
/// (the device may not be capable, and CI never is).
struct FoundationModelLanguageModelTests {
    // MARK: - doGenerate shape

    @Test("doGenerate returns one .text part with TranslationResult JSON, stop, nil usage")
    func doGenerateShape() async throws {
        let model = FoundationModelLanguageModel { _ in
            [TranslationLine(number: 1, text: "Hallo"), TranslationLine(number: 2, text: "Wereld")]
        }
        let prompt: LanguageModelV3Prompt = [
            .system(content: "instructions", providerOptions: nil),
            .user(content: [.text(.init(text: "1. EN: Hello\n2. EN: World"))], providerOptions: nil),
        ]
        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.finishReason.unified == .stop)
        #expect(result.usage.inputTokens.total == nil)
        #expect(result.usage.outputTokens.total == nil)
        #expect(result.content.count == 1)

        guard case let .text(textPart) = result.content[0] else {
            Issue.record("expected a single .text content part")
            return
        }
        let decoded = try JSONDecoder().decode(TranslationResult.self, from: Data(textPart.text.utf8))
        #expect(decoded.translations == [
            TranslationLine(number: 1, text: "Hallo"),
            TranslationLine(number: 2, text: "Wereld"),
        ])
    }

    @Test("the injected generator receives the full standardized prompt")
    func passesFullPrompt() async throws {
        let captured = LockIsolated<LanguageModelV3Prompt>([])
        let model = FoundationModelLanguageModel { prompt in
            captured.withValue { $0 = prompt }
            return []
        }
        let prompt: LanguageModelV3Prompt = [
            .system(content: "sys", providerOptions: nil),
            .user(content: [.text(.init(text: "1. EN: Hi"))], providerOptions: nil),
        ]
        _ = try await model.doGenerate(options: .init(prompt: prompt))
        #expect(captured.value.count == 2)
    }

    @Test("doStream wraps doGenerate and emits the same text then finishes")
    func doStreamWrapsGenerate() async throws {
        let model = FoundationModelLanguageModel { _ in
            [TranslationLine(number: 1, text: "Hoi")]
        }
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "1. EN: Hi"))], providerOptions: nil),
        ]
        let streamResult = try await model.doStream(options: .init(prompt: prompt))

        var text = ""
        var finished = false
        for try await part in streamResult.stream {
            switch part {
            case let .textDelta(_, delta, _): text += delta
            case .finish: finished = true
            default: break
            }
        }
        #expect(finished)
        let decoded = try JSONDecoder().decode(TranslationResult.self, from: Data(text.utf8))
        #expect(decoded.translations == [TranslationLine(number: 1, text: "Hoi")])
    }

    @Test("on-device errors propagate out of doGenerate")
    func errorPropagates() async {
        struct Boom: Error {}
        let model = FoundationModelLanguageModel { _ in throw Boom() }
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "1. EN: Hi"))], providerOptions: nil),
        ]
        await #expect(throws: Boom.self) {
            _ = try await model.doGenerate(options: .init(prompt: prompt))
        }
    }

    // MARK: - Prompt extraction helpers

    @Test("systemText concatenates the system messages")
    func extractsSystemText() {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "rule one", providerOptions: nil),
            .user(content: [.text(.init(text: "1. EN: Hi"))], providerOptions: nil),
        ]
        #expect(FoundationModelLanguageModel.systemText(from: prompt) == "rule one")
    }

    @Test("userText concatenates the user text parts, including NL refine lines")
    func extractsUserText() {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "rules", providerOptions: nil),
            .user(content: [.text(.init(text: "1. EN: Hello\n1. NL: Hoi"))], providerOptions: nil),
        ]
        let text = FoundationModelLanguageModel.userText(from: prompt)
        #expect(text.contains("EN: Hello"))
        #expect(text.contains("NL: Hoi"))
    }

    // MARK: - End-to-end through the unified step (no Apple Intelligence)

    @Test("runs through AISDKTranslationStep and writes translations back by number")
    func endToEndThroughUnifiedStep() async throws {
        let model = FoundationModelLanguageModel { prompt in
            // Map by extracting the source lines, then return reordered results to
            // prove number-based mapping, not positional.
            let lines = CustomTranslationPrompt.sourceLines(from: prompt)
            return lines.reversed().map {
                TranslationLine(number: $0.number, text: $0.text == "Hello" ? "Hallo" : "Wereld")
            }
        }
        let step = AISDKTranslationStep(model: model, mode: .translate)

        var items = [
            TranslationItem(sourceText: "Hello", lineID: "a"),
            TranslationItem(sourceText: "World", lineID: "b"),
        ]
        try await step.process(&items)
        #expect(items[0].currentText == "Hallo")
        #expect(items[1].currentText == "Wereld")
    }

    // MARK: - LanguageModelV3 identity

    @Test("identifies itself as the on-device FoundationModels backend")
    func identity() {
        let model = FoundationModelLanguageModel { _ in [] }
        #expect(model.provider == "apple-foundation-models")
        #expect(model.modelId == "apple-on-device")
    }
}
